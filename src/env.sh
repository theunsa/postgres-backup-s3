if [ -z "$RCLONE_REMOTE" ]; then
  echo "You need to set the RCLONE_REMOTE environment variable."
  exit 1
fi

if [ -z "$POSTGRES_DATABASES" ]; then
  echo "You need to set the POSTGRES_DATABASES environment variable."
  exit 1
fi

if [ -z "$POSTGRES_HOST" ]; then
  echo "You need to set the POSTGRES_HOST environment variable."
  exit 1
fi

if [ -z "$POSTGRES_USER" ]; then
  echo "You need to set the POSTGRES_USER environment variable."
  exit 1
fi

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "You need to set the POSTGRES_PASSWORD environment variable."
  exit 1
fi

# rclone is configured entirely through RCLONE_CONFIG_<NAME>_* variables the
# user supplies; it needs no config file. Normalize away a trailing slash so
# "${RCLONE_REMOTE}/${database}" is always well formed.
RCLONE_REMOTE="${RCLONE_REMOTE%/}"

export PGPASSWORD=$POSTGRES_PASSWORD
