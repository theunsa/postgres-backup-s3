# postgres-backup-s3

Periodic `pg_dump` backups of a PostgreSQL database to any S3-compatible
storage (AWS S3, Cloudflare R2, Hetzner Object Storage, MinIO), with
one-command restore. One small Alpine image, ~60 lines of shell.

A maintained revival of [eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3)
(archived June 2025), originally based on
[schickling/postgres-backup-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3). MIT.

Images are tagged by the PostgreSQL major version they back up:

```
ghcr.io/theunsa/postgres-backup-s3:15
ghcr.io/theunsa/postgres-backup-s3:16
ghcr.io/theunsa/postgres-backup-s3:17
ghcr.io/theunsa/postgres-backup-s3:18
```

Match the tag to your server's major version — `pg_dump` refuses to dump a
server newer than itself.

## Usage with Kamal

Run it as an accessory next to your database accessory:

```yaml
accessories:
  db:
    image: postgres:18
    host: 1.2.3.4
    # ...

  db-backup:
    image: ghcr.io/theunsa/postgres-backup-s3:18
    host: 1.2.3.4
    env:
      clear:
        SCHEDULE: '@hourly'        # go-cron spec; omit to run once and exit
        BACKUP_KEEP_DAYS: 30       # prune older backups from the bucket
        S3_REGION: auto            # 'auto' for Cloudflare R2
        S3_ENDPOINT: https://<account-id>.r2.cloudflarestorage.com
        S3_BUCKET: myapp-db-backups
        S3_PREFIX: backup
        POSTGRES_HOST: myapp-db    # Kamal accessory container name
        POSTGRES_DATABASE: myapp_production
        POSTGRES_USER: myapp
      secret:
        - POSTGRES_PASSWORD
        - S3_ACCESS_KEY_ID
        - S3_SECRET_ACCESS_KEY
        - PASSPHRASE               # optional: GPG-encrypt the dumps
```

Then:

```sh
kamal accessory boot db-backup
```

Ad-hoc backup and restore:

```sh
kamal accessory exec db-backup --reuse "sh backup.sh"
kamal accessory exec db-backup --reuse "sh restore.sh"                      # latest
kamal accessory exec db-backup --reuse "sh restore.sh 2026-06-12T03:00:00"  # specific
```

> [!CAUTION]
> Restore drops and re-creates all database objects (`pg_restore --clean --if-exists`).

## Usage with Docker Compose

```yaml
services:
  postgres:
    image: postgres:18
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password

  backup:
    image: ghcr.io/theunsa/postgres-backup-s3:18
    environment:
      SCHEDULE: '@daily'
      BACKUP_KEEP_DAYS: 7
      S3_REGION: region
      S3_ACCESS_KEY_ID: key
      S3_SECRET_ACCESS_KEY: secret
      S3_BUCKET: my-bucket
      S3_PREFIX: backup
      POSTGRES_HOST: postgres
      POSTGRES_DATABASE: dbname
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
```

## Environment variables

| Variable | Required | Notes |
|---|---|---|
| `POSTGRES_HOST` | yes | |
| `POSTGRES_DATABASE` | yes | |
| `POSTGRES_USER` | yes | |
| `POSTGRES_PASSWORD` | yes | |
| `POSTGRES_PORT` | no | default `5432` |
| `S3_BUCKET` | yes | |
| `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY` | yes* | *or instance-profile credentials |
| `S3_REGION` | no | default `us-west-1`; use `auto` for R2 |
| `S3_ENDPOINT` | no | set for non-AWS providers, e.g. R2 |
| `S3_PREFIX` | no | key prefix, default `backup` |
| `S3_S3V4` | no | `yes` forces v4 signatures |
| `SCHEDULE` | no | [go-cron spec](https://pkg.go.dev/github.com/robfig/cron#hdr-Predefined_schedules) (`@hourly`, `0 3 * * *`, …); omit to back up once and exit |
| `BACKUP_KEEP_DAYS` | no | delete bucket objects older than N days after each backup |
| `PASSPHRASE` | no | GPG symmetric encryption of dumps |
| `PGDUMP_EXTRA_OPTS` | no | appended to `pg_dump` |
| `HEARTBEAT_URL` | no | GET after each successful backup — point at [healthchecks.io](https://healthchecks.io)/Uptime Kuma so a silently-failing backup alerts you |

Backups are `pg_dump --format=custom`, stored as
`s3://$S3_BUCKET/$S3_PREFIX/<database>_<timestamp>.dump[.gpg]`.

## Cloudflare R2 notes

- `S3_ENDPOINT: https://<account-id>.r2.cloudflarestorage.com`, `S3_REGION: auto`.
- Use a bucket-scoped R2 API token (Object Read & Write on the backup bucket only).
- `BACKUP_KEEP_DAYS` handles pruning; an R2 lifecycle rule on the bucket is a
  good belt-and-braces second layer.

## Development

Self-contained local rig (Postgres 18 + MinIO), no real credentials:

```sh
docker compose up -d --build
docker compose run --rm backup sh backup.sh
docker compose run --rm backup sh restore.sh
docker compose down -v
```

`ALPINE_VERSION` must ship the matching `postgresqlNN-client` package — see
the [build workflow](.github/workflows/build-and-push-images.yml) for the mapping.

## Changes vs the archived upstream

- PostgreSQL 15–18 (client package pinned to the image's major version)
- Fixed `S3_PREFIX`/`S3_PATH` env var mismatch
- Optional `HEARTBEAT_URL` dead-man-switch ping
- Publishes to GHCR via plain `GITHUB_TOKEN` (no registry secrets)
- Dropped legacy Docker-links host discovery
