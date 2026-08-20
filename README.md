# postgres-backup-s3

Periodic `pg_dump` backups of one or more PostgreSQL databases to any
S3-compatible storage (AWS S3, Cloudflare R2, Hetzner Object Storage, MinIO),
with one-command restore — and a `rehearse` command that proves a backup
actually restores. One small Alpine image, ~150 lines of shell.

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
        RCLONE_REMOTE: r2:myapp-db-backups/backup
        RCLONE_CONFIG_R2_TYPE: s3
        RCLONE_CONFIG_R2_PROVIDER: Cloudflare
        RCLONE_CONFIG_R2_REGION: auto
        RCLONE_CONFIG_R2_ENDPOINT: https://<account-id>.r2.cloudflarestorage.com
        POSTGRES_HOST: myapp-db    # Kamal accessory container name
        POSTGRES_DATABASES: myapp_production myapp_analytics
        POSTGRES_USER: myapp
      secret:
        - POSTGRES_PASSWORD
        - RCLONE_CONFIG_R2_ACCESS_KEY_ID
        - RCLONE_CONFIG_R2_SECRET_ACCESS_KEY
        - PASSPHRASE               # optional: GPG-encrypt the dumps
```

Then:

```sh
kamal accessory boot db-backup
```

Ad-hoc backup, restore and rehearsal:

```sh
kamal accessory exec db-backup --reuse "sh backup.sh"
kamal accessory exec db-backup --reuse "sh restore.sh myapp_production"                      # latest
kamal accessory exec db-backup --reuse "sh restore.sh myapp_production 2026-06-12T03:00:00"  # specific
kamal accessory exec db-backup --reuse "sh rehearse.sh myapp_production"                     # test-restore
```

> [!CAUTION]
> Restore drops and re-creates all database objects (`pg_restore --clean --if-exists`).
> `rehearse.sh` never touches the live database — it restores into a scratch one.

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
      RCLONE_REMOTE: s3:my-bucket/backup
      RCLONE_CONFIG_S3_TYPE: s3
      RCLONE_CONFIG_S3_PROVIDER: AWS
      RCLONE_CONFIG_S3_REGION: us-east-1
      RCLONE_CONFIG_S3_ACCESS_KEY_ID: key
      RCLONE_CONFIG_S3_SECRET_ACCESS_KEY: secret
      POSTGRES_HOST: postgres
      POSTGRES_DATABASES: app_one app_two
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
```

## Environment variables

| Variable | Required | Notes |
|---|---|---|
| `RCLONE_REMOTE` | yes | full destination, e.g. `r2:my-bucket/backup` |
| `RCLONE_CONFIG_<NAME>_*` | yes | standard [rclone env config](https://rclone.org/docs/#config-file) for the backend named in `RCLONE_REMOTE`; no config file is ever written |
| `POSTGRES_HOST` | yes | |
| `POSTGRES_USER` | yes | |
| `POSTGRES_PASSWORD` | yes | |
| `POSTGRES_DATABASES` | yes | space-separated list; one database is just a list of one |
| `POSTGRES_PORT` | no | default `5432` |
| `SCHEDULE` | no | [go-cron spec](https://pkg.go.dev/github.com/robfig/cron#hdr-Predefined_schedules) (`@hourly`, `0 3 * * *`, …); omit to back up once and exit |
| `PASSPHRASE` | no | GPG symmetric encryption of dumps |
| `BACKUP_KEEP_DAYS` | no | delete objects older than N days after each backup; empty = never delete |
| `PGDUMP_EXTRA_OPTS` | no | appended to `pg_dump` |
| `HEARTBEAT_URL` | no | GET after a fully successful run — point at [healthchecks.io](https://healthchecks.io)/Uptime Kuma so a silently-failing backup alerts you |
| `KEEP_SCRATCH` | no | `rehearse.sh` only: `1` keeps the scratch database for inspection |

Backups are `pg_dump --format=custom`, stored one directory per database:

```
$RCLONE_REMOTE/<database>/<database>_<timestamp>.dump[.gpg]
```

Every database in `POSTGRES_DATABASES` is dumped on each run. If one fails, the
rest still run; the failures are reported, the heartbeat is *not* pinged, and
the run exits non-zero.

## Rehearsing a backup

A backup you have never restored is a hypothesis. `rehearse.sh` turns it into a
fact:

```sh
docker compose exec backup sh rehearse.sh myapp_production
docker compose exec backup sh rehearse.sh myapp_production 2026-06-12T03:00:00
```

It fetches the dump (latest unless a timestamp is given), decrypts it, creates a
uniquely-named scratch database, `pg_restore --exit-on-error`s into it, counts
the restored relations, prints the count, and drops the scratch database again —
also on failure. A restore that yields zero relations is a **failed** rehearsal
and exits non-zero. `KEEP_SCRATCH=1` leaves the scratch database in place so you
can poke at it.

The `POSTGRES_USER` role needs the `CREATEDB` attribute for this:

```sql
ALTER ROLE myapp CREATEDB;
```

Run it on a schedule (or after a restore-procedure change) and you will find out
about an unrestorable backup on your terms rather than during an outage.

## Not just S3

The transfer layer is [rclone](https://rclone.org), so any rclone backend works —
Backblaze B2, Google Cloud Storage, Azure Blob, SFTP, WebDAV, a local volume.
Only the `RCLONE_CONFIG_<NAME>_*` variables and `RCLONE_REMOTE` change; nothing
in the container assumes S3. For example, Backblaze B2:

```yaml
RCLONE_CONFIG_B2_TYPE: b2
RCLONE_CONFIG_B2_ACCOUNT: <key-id>
RCLONE_CONFIG_B2_KEY: <application-key>
RCLONE_REMOTE: b2:myapp-db-backups/backup
```

The repo and image keep the `postgres-backup-s3` name; S3-compatible storage is
still the common case.

## Retention

`BACKUP_KEEP_DAYS` makes the backup container delete its own old objects
(`rclone delete --min-age <N>d` per database directory). That is convenient, and
it is also the weakest possible arrangement: the same credential that writes
backups can erase them, so anything that compromises or bugs the container can
take the history with it.

**Prefer provider-side expiry.** Leave `BACKUP_KEEP_DAYS` unset and let the
bucket's own lifecycle rule expire old objects. The backup token then only ever
needs to add objects, and retention is enforced by something the container
cannot talk to.

### Cloudflare R2

R2 is worth spelling out, because its token model has a sharp edge:

- **There is no write-without-delete token tier.** R2 API tokens come in four
  flavours — Admin Read & Write, Admin Read only, Object Read & Write, and
  Object Read only. The narrowest token that can upload a backup (Object Read &
  Write) can also delete one. You cannot solve this with permissions alone.
- **Bucket locks are the answer.** An R2 bucket lock prevents deletion *and*
  overwriting of matching objects for a retention period, regardless of what the
  token is allowed to do, and takes precedence over lifecycle rules.
- **The lock period must be shorter than the lifecycle expiry.** If the lock
  outlasts the expiry rule, the lock wins and the lifecycle deletion simply
  fails, so objects accumulate forever. Set, for example, a 7-day lock with a
  30-day expiry.

So on R2: bucket lock for immutability, lifecycle rule for expiry, lock period
< expiry period, and `BACKUP_KEEP_DAYS` unset. Note that with a bucket lock in
place, `BACKUP_KEEP_DAYS` would fail on locked objects anyway — another reason
to leave it alone.

## Development

Self-contained local rig (Postgres 18 + MinIO), no real credentials:

```sh
docker compose up -d --build
docker compose run --rm backup sh backup.sh
docker compose run --rm backup sh restore.sh app_one
docker compose run --rm backup sh rehearse.sh app_one
docker compose down -v
```

The rig creates two databases (`app_one`, `app_two`) so the multi-database loop
is actually exercised, and points rclone at MinIO with `RCLONE_CONFIG_MINIO_*`.

`ALPINE_VERSION` must ship the matching `postgresqlNN-client` package — see
the [build workflow](.github/workflows/build-and-push-images.yml) for the mapping.

## Changes vs the archived upstream

- PostgreSQL 15–18 (client package pinned to the image's major version)
- rclone instead of aws-cli: any rclone backend, no config file, ~113MB smaller image
- Multiple databases per container (`POSTGRES_DATABASES`), one key prefix each
- `rehearse.sh`: automated restore rehearsal into a scratch database
- Optional `HEARTBEAT_URL` dead-man-switch ping, fired only on a fully clean run
- Publishes to GHCR via plain `GITHUB_TOKEN` (no registry secrets)
- Dropped legacy Docker-links host discovery
