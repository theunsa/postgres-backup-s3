#! /bin/sh

set -eux
set -o pipefail

apk update

# pg_dump/pg_restore matching the server major version (POSTGRES_VERSION build arg)
apk add postgresql${POSTGRES_VERSION}-client

apk add gnupg

# rclone talks to any rclone backend (S3, R2, B2, SFTP, ...) and is configured
# purely through RCLONE_* environment variables — no config file on disk.
apk add rclone

# curl stays installed: used for the optional HEARTBEAT_URL ping in backup.sh
apk add curl

# install go-cron
curl -L https://github.com/ivoronin/go-cron/releases/download/v0.0.5/go-cron_0.0.5_linux_${TARGETARCH}.tar.gz -O
tar xvf go-cron_0.0.5_linux_${TARGETARCH}.tar.gz
rm go-cron_0.0.5_linux_${TARGETARCH}.tar.gz
mv go-cron /usr/local/bin/go-cron
chmod u+x /usr/local/bin/go-cron

# cleanup
rm -rf /var/cache/apk/*
