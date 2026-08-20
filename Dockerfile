ARG ALPINE_VERSION
FROM alpine:${ALPINE_VERSION}
ARG TARGETARCH
ARG POSTGRES_VERSION

ADD src/install.sh install.sh
RUN sh install.sh && rm install.sh

# Destination, e.g. r2:my-bucket/backup. The backend itself is configured with
# the standard RCLONE_CONFIG_<NAME>_* variables, which the user supplies.
ENV RCLONE_REMOTE=''
ENV POSTGRES_HOST=''
ENV POSTGRES_PORT=5432
ENV POSTGRES_USER=''
ENV POSTGRES_PASSWORD=''
ENV POSTGRES_DATABASES=''
ENV PGDUMP_EXTRA_OPTS=''
ENV SCHEDULE=''
ENV PASSPHRASE=''
ENV BACKUP_KEEP_DAYS=''
ENV HEARTBEAT_URL=''
ENV KEEP_SCRATCH=''

ADD src/run.sh run.sh
ADD src/env.sh env.sh
ADD src/backup.sh backup.sh
ADD src/restore.sh restore.sh
ADD src/rehearse.sh rehearse.sh

CMD ["sh", "run.sh"]
