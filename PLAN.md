# postgres-backup-s3

Standalone, public, reusable Docker image: periodic `pg_dump` of one or more
Postgres databases to any rclone backend — S3-compatible storage (AWS S3,
Cloudflare R2, Hetzner, MinIO) being the common case — with one-command restore
and an automated restore rehearsal. Built for Kamal accessory use but plain
Docker works.

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
`postgresqlNN-client` + `rclone` + `gnupg` + pinned `go-cron`.

`rclone` rather than `aws-cli`: it is ~113MB smaller in the image, needs no
config file (everything comes from `RCLONE_CONFIG_<NAME>_*` env vars), is always
SigV4, and opens every rclone backend rather than S3 alone. `rclone delete
--min-age Nd` also replaces the old `list-objects --query | xargs aws s3 rm`
pipeline, which fed the literal string `None` to `s3 rm` when nothing matched.

Container behavior:
- `SCHEDULE` set → go-cron runs `backup.sh` on that cron spec, container stays up.
- `SCHEDULE` empty → single backup, exit.
- `docker exec <c> sh backup.sh` → ad-hoc backup of every database in
  `POSTGRES_DATABASES`; a failure on one does not skip the others, and the run
  exits non-zero.
- `docker exec <c> sh restore.sh <database> [timestamp]` → restore latest or
  specific (drops + recreates objects via `pg_restore --clean --if-exists`).
- `docker exec <c> sh rehearse.sh <database> [timestamp]` → restore into a
  throwaway scratch database, assert a non-zero relation count, drop it again.
- `PASSPHRASE` set → GPG symmetric encryption of the dump.
- `BACKUP_KEEP_DAYS` set → prune older objects after each backup (provider-side
  lifecycle expiry is the better option; see README).
- `RCLONE_REMOTE` + `RCLONE_CONFIG_<NAME>_*` → any rclone backend (R2, B2, …).

Object layout is one directory per database:
`$RCLONE_REMOTE/<database>/<database>_<timestamp>.dump[.gpg]`, which keeps
listing, retention and bucket-lock/lifecycle scoping per-database.

## Changes vs upstream

1. ~~**Fix `S3_PREFIX` bug**: upstream Dockerfile sets `S3_PATH` but scripts read
   `S3_PREFIX` under `set -u`.~~ Superseded by (6): there are no `S3_*` variables
   left — the bucket and prefix now live inside `RCLONE_REMOTE`.
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
6. **rclone instead of aws-cli**: smaller image, no config file, any backend.
   Every `S3_*` variable is gone, replaced by `RCLONE_REMOTE` +
   `RCLONE_CONFIG_<NAME>_*`.
7. **Multi-database**: `POSTGRES_DATABASES` is a space-separated list; each
   database gets its own key prefix, and one failure does not hide the others.
8. **`rehearse.sh`**: restore rehearsal into a scratch database with a
   non-empty-restore assertion — the thing that turns "we have backups" into
   "we have restores".

## Repo layout

```
Dockerfile
src/install.sh  src/run.sh  src/env.sh  src/backup.sh  src/restore.sh
src/rehearse.sh
.github/workflows/build-and-push-images.yml
docker-compose.yaml   # local dev/test rig (postgres + minio + backup)
template.env
README.md  LICENSE  PLAN.md
```

## Non-goals

- WAL archiving / PITR (wal-g, pgBackRest) — wrong tradeoff for small DBs;
  use those directly if you need point-in-time recovery.
- Multi-host fan-out — one container per Postgres server. (Multiple databases
  on the *same* server are supported: `POSTGRES_DATABASES` is a list.)
- Notifications beyond the heartbeat URL.

## Verification

- `docker build` for pg 18 locally; run against a throwaway postgres:18 +
  MinIO via docker-compose: backup of two databases, list objects under the
  per-database prefixes, restore one, `rehearse.sh` both, prune path with
  `BACKUP_KEEP_DAYS`, and the zero-relation rehearsal failure case.
- First real deploy: manual `backup.sh`, then `rehearse.sh` before trusting the
  schedule — and on a schedule thereafter.
