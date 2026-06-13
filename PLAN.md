# postgres-backup-s3

Standalone, public, reusable Docker image: periodic `pg_dump` of a Postgres
database to any S3-compatible storage (AWS S3, Cloudflare R2, Hetzner, MinIO),
with one-command restore. Built for Kamal accessory use but plain Docker works.

Fork/revival of [eeshugerman/postgres-backup-s3](https://github.com/eeshugerman/postgres-backup-s3)
(archived June 2025), itself based on
[schickling/postgres-backup-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3).
Both MIT.

## Why own it

- Upstream archived; forks stop at postgres client 17.
- Whole thing is ~60 lines of shell. Owning it removes the abandonment risk
  and keeps the client version in lockstep with the server we deploy.

## Design

One image per Postgres major version, tagged `:15` `:16` `:17` `:18`,
published to `ghcr.io/theunsa/postgres-backup-s3`. Alpine base + matching
`postgresqlNN-client` + `aws-cli` + `gnupg` + pinned `go-cron`.

Container behavior (unchanged from upstream):
- `SCHEDULE` set → go-cron runs `backup.sh` on that cron spec, container stays up.
- `SCHEDULE` empty → single backup, exit.
- `docker exec <c> sh backup.sh` → ad-hoc backup.
- `docker exec <c> sh restore.sh [timestamp]` → restore latest or specific
  (drops + recreates objects via `pg_restore --clean --if-exists`).
- `PASSPHRASE` set → GPG symmetric encryption of the dump.
- `BACKUP_KEEP_DAYS` set → prune older S3 objects after each backup.
- `S3_ENDPOINT` → any S3-compatible provider (R2 etc.).

## Changes vs upstream

1. **Fix `S3_PREFIX` bug**: upstream Dockerfile sets `S3_PATH` but scripts read
   `S3_PREFIX` under `set -u`. Use `S3_PREFIX` (default `backup`) everywhere.
2. **Postgres 15–18**: install explicit `postgresql${POSTGRES_VERSION}-client`
   (not the Alpine default), matrix:
   | pg | alpine |
   |----|--------|
   | 15 | 3.22 |
   | 16 | 3.22 |
   | 17 | 3.22 |
   | 18 | 3.23 |
3. **GHCR via GITHUB_TOKEN**: workflow pushes to ghcr; no DockerHub secrets.
   Multi-arch amd64 + arm64. Updated action versions.
4. **Optional `HEARTBEAT_URL`**: curl GET after a successful backup
   (healthchecks.io / Uptime Kuma style dead-man switch). Backups that fail
   silently are the classic trap; this is 3 lines.
5. **README**: Kamal accessory example (the primary use case) + R2 notes +
   restore runbook.

## Repo layout

```
Dockerfile
src/install.sh  src/run.sh  src/env.sh  src/backup.sh  src/restore.sh
.github/workflows/build-and-push-images.yml
docker-compose.yaml   # local dev/test rig (postgres + minio + backup)
template.env
README.md  LICENSE  PLAN.md
```

## Non-goals

- WAL archiving / PITR (wal-g, pgBackRest) — wrong tradeoff for small DBs;
  use those directly if you need point-in-time recovery.
- Multi-database / multi-host fan-out — run one container per database.
- Notifications beyond the heartbeat URL.

## Verification

- `docker build` for pg 18 locally; run against a throwaway postgres:18 +
  MinIO via docker-compose: backup, list object, restore, prune path.
- First real deploy: manual `backup.sh`, then `restore.sh` rehearsal against
  a scratch database before trusting the schedule.
