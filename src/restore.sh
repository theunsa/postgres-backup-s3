#! /bin/sh
#
# Usage: sh restore.sh <database> [timestamp]
#
# Restores the latest backup of <database>, or the one taken at [timestamp].

set -eu
set -o pipefail

source ./env.sh

if [ $# -lt 1 ]; then
  echo "Usage: sh restore.sh <database> [timestamp]"
  exit 1
fi

database="$1"

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

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

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

# pg_restore exits non-zero whenever it *ignores* an error, which is routine
# for --clean against objects the restoring role does not own. Letting `set -e`
# abort here would kill the script before it could say what actually happened,
# which is why upstream omitted `set -e` entirely. Capture the status instead
# and report it, so a partial restore is never mistaken for a clean one.
echo "Restoring ${database} from backup..."
restore_rc=0
pg_restore -h "$POSTGRES_HOST" \
           -p "$POSTGRES_PORT" \
           -U "$POSTGRES_USER" \
           -d "$database" \
           --clean --if-exists \
           "$dump_file" || restore_rc=$?

if [ "$restore_rc" -ne 0 ]; then
  echo "Restore of ${database} finished with IGNORED ERRORS (pg_restore exit ${restore_rc})."
  echo "Review the output above and verify the database before trusting it."
  exit "$restore_rc"
fi

echo "Restore of ${database} complete."
