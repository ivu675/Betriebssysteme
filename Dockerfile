# author: <dein Name>    version: 1.0
#
# Dockerfile für den Monitoring-Container.
#
# Idee:
# - basiert auf einem schlanken Alpine-Linux
# - installiert bash als Shell
# - legt einen eigenen, nicht privilegierten Benutzer "app" an
# - kopiert die Skripte monitor.sh und healthcheck.sh ins Image
# - setzt Standard-Umgebungsvariablen für das Monitoring
# - startet am Ende das Monitoring-Skript als Container-Command
#
# Die eigentliche Logik (Messen und Loggen) passiert in monitor.sh,
# dieses Dockerfile sorgt nur für die passende Umgebung im Container.

FROM alpine:3.20

# bash nachinstallieren
RUN apk add --no-cache bash

# eigenen User und Gruppe anlegen, damit nichts als root läuft
RUN addgroup -g 10001 app && adduser -D -u 10001 -G app app

WORKDIR /app

# Monitoring- und Healthcheck-Skript ins Image kopieren
COPY monitor.sh healthcheck.sh ./

# Skripte ausführbar machen und Verzeichnis für optionale Logs anlegen
RUN chmod +x /app/monitor.sh /app/healthcheck.sh \
    && mkdir -p /data \
    && chown -R app:app /data

# ab hier alles als "app"-User ausführen
USER app

# Standardwerte für das Monitoring; können über docker-compose überschrieben werden
ENV INTERVAL=10 \
    LOG_FILE=/dev/stdout \
    HOST_PROC=/host_proc \
    HOST_SYS=/host_sys \
    HOST_ROOT=/host_root

# Container startet direkt das Monitoring-Skript
CMD ["bash", "/app/monitor.sh"]

