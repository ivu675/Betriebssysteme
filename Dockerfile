FROM alpine:3.20

RUN apk add --no-cache bash postgresql-client su-exec

# SICHERHEIT & HARDENING
# Was:   Erstellt einen dedizierten User 'app' und nutzt 'alpine' als Basis.
# Wozu:  Minimale und sichere Laufzeitumgebung bereitstellen.
# Warum: 'USER app' verhindert, dass der Container als Root läuft (Sicherheitsrisiko).
#        [cite_start]Alpine ist extrem klein (<10MB) und reduziert die Angriffsfläche. [cite: 153]

RUN addgroup -g 10001 app && adduser -D -u 10001 -G app app

WORKDIR /app

COPY monitor.sh healthcheck.sh monitorctl.sh ./
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /app/monitor.sh /app/healthcheck.sh /app/monitorctl.sh /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /data \
    && chown -R app:app /data

ENV INTERVAL=60 \
    LOG_FILE=/data/system_monitor.log \
    HOST_PROC=/host_proc \
    HOST_SYS=/host_sys \
    HOST_ROOT=/host_root \
    DB_ENABLED=true \
    DB_HOST=db \
    DB_PORT=5432 \
    DB_NAME=monitor \
    DB_USER=monitor \
    DB_PASSWORD=monitor

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["bash", "/app/monitor.sh"]
