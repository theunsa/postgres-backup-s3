#! /bin/sh
#
# Usage: sh rehearse.sh <database> [timestamp]
#
# Proves a backup actually restores: fetches it, decrypts it, restores it into
# a freshly created scratch database, checks the result is non-empty, then
# drops the scratch database again. Set KEEP_SCRATCH=1 to keep it around.
#
# Requires the POSTGRES_USER role to have the CREATEDB attribute.

set -eu
set -o pipefail

source ./env.sh

if [ $# -lt 1 ]; then
  echo "Usage: sh rehearse.sh <database> [timestamp]"
  exit 1
fi

database="$1"

conn_opts="-h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER"

# Postgres identifiers are capped at 63 bytes. Build the name ourselves rather
# than letting the server silently truncate it: 'rehearse_' (9) + name (<=30)
# + '_' + 14-digit stamp + '_' + pid (<=8) stays inside the limit.
safe_name=$(printf '%s' "$database" | tr -c 'A-Za-z0-9_' '_' | cut -c1-30)
scratch_db="rehearse_${safe_name}_$(date +%Y%m%d%H%M%S)_$$"
scratch_db=$(printf '%s' "$scratch_db" | cut -c1-63)

work_dir=$(mktemp -d)
scratch_created=''

cleanup() {
  rm -rf "$work_dir"
  if [ -n "$scratch_created" ]; then
    if [ "${KEEP_SCRATCH:-}" = "1" ]; then
      echo "KEEP_SCRATCH=1 — leaving scratch database ${scratch_db} in place."
    else
      echo "Dropping scratch database ${scratch_db}..."
      dropdb $conn_opts --if-exists "$scratch_db" || \
        echo "WARNING: failed to drop scratch database ${scratch_db}."
    fi
  fi
}
trap cleanup EXIT

if [ -z "$PASSPHRASE" ]; then
  file_type=".dump"
else
  file_type=".dump.gpg"
fi

remote_dir="${RCLONE_REMOTE}/${database}"

if [ $# -ge 2 ]; then
  file_name="${database}_${2}${file_type}"
else
  echo "Finding latest backup of ${database}..."
  file_name=$(
    rclone lsf "$remote_dir" \
      | grep -- "${file_type}\$" \
      | sort \
      | tail -n 1
  )
  if [ -z "$file_name" ]; then
    echo "No backup found for database '${database}' at ${remote_dir}."
    exit 1
  fi
fi

echo "Fetching ${remote_dir}/${file_name}..."
rclone copyto "${remote_dir}/${file_name}" "${work_dir}/${file_name}"

if [ -n "$PASSPHRASE" ]; then
  echo "Decrypting backup..."
  gpg --decrypt --batch --passphrase "$PASSPHRASE" \
      --output "${work_dir}/db.dump" "${work_dir}/${file_name}"
  dump_file="${work_dir}/db.dump"
else
  dump_file="${work_dir}/${file_name}"
fi

echo "Creating scratch database ${scratch_db}..."
createdb $conn_opts "$scratch_db"
scratch_created=1

# A rehearsal is deliberately strict: --exit-on-error means any error at all
# fails the run, unlike restore.sh which tolerates ignorable ones.
echo "Restoring ${file_name} into ${scratch_db}..."
if ! pg_restore $conn_opts -d "$scratch_db" --exit-on-error "$dump_file"; then
  echo "REHEARSAL FAILED: ${file_name} did not restore cleanly into ${scratch_db}."
  exit 1
fi

relations=$(
  psql $conn_opts -d "$scratch_db" -tAc "
    SELECT count(*)
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S')
       AND n.nspname NOT IN ('pg_catalog', 'information_schema')
       AND n.nspname !~ '^pg_toast'"
)

if [ "$relations" -eq 0 ]; then
  echo "REHEARSAL FAILED: ${file_name} restored 0 relations into ${scratch_db}."
  exit 1
fi

echo "Rehearsal OK: ${file_name} restored ${relations} relations into ${scratch_db}."
