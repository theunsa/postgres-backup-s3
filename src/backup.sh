#! /bin/sh

set -eu
set -o pipefail

source ./env.sh

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
failed=''

for database in $POSTGRES_DATABASES; do
  dump_file="${work_dir}/${database}_${timestamp}.dump"

  echo "Creating backup of $database database..."
  if ! pg_dump --format=custom \
               -h "$POSTGRES_HOST" \
               -p "$POSTGRES_PORT" \
               -U "$POSTGRES_USER" \
               -d "$database" \
               $PGDUMP_EXTRA_OPTS \
               --file "$dump_file"; then
    echo "ERROR: pg_dump failed for database '$database'."
    failed="${failed}${database} "
    rm -f "$dump_file"
    continue
  fi

  if [ -n "$PASSPHRASE" ]; then
    echo "Encrypting backup of $database..."
    if ! gpg --symmetric --batch --yes --passphrase "$PASSPHRASE" "$dump_file"; then
      echo "ERROR: gpg encryption failed for database '$database'."
      failed="${failed}${database} "
      rm -f "$dump_file" "${dump_file}.gpg"
      continue
    fi
    rm -f "$dump_file"
    local_file="${dump_file}.gpg"
  else
    local_file="$dump_file"
  fi

  remote_path="${RCLONE_REMOTE}/${database}/$(basename "$local_file")"

  echo "Uploading backup of $database to ${remote_path}..."
  if ! rclone copyto "$local_file" "$remote_path"; then
    echo "ERROR: upload failed for database '$database'."
    failed="${failed}${database} "
    rm -f "$local_file"
    continue
  fi
  rm -f "$local_file"

  if [ -n "$BACKUP_KEEP_DAYS" ]; then
    echo "Removing backups of $database older than ${BACKUP_KEEP_DAYS} days..."
    if ! rclone delete --min-age "${BACKUP_KEEP_DAYS}d" "${RCLONE_REMOTE}/${database}"; then
      echo "ERROR: retention pruning failed for database '$database'."
      failed="${failed}${database} "
      continue
    fi
  fi

  echo "Backup of $database complete."
done

if [ -n "$failed" ]; then
  echo "Backup FAILED for: ${failed% }"
  exit 1
fi

echo "All backups complete."

if [ -n "$HEARTBEAT_URL" ]; then
  echo "Pinging heartbeat URL..."
  curl -fsS -m 10 --retry 3 -o /dev/null "$HEARTBEAT_URL"
fi
