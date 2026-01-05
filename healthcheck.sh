#!/usr/bin/env bash
# author: <dein Name>       version: 1.0
#
# Healthcheck-Skript für den Container.
# Prüft, ob die vom Monitoring-Skript angelegte Heartbeat-Datei noch frisch ist.
#
# Idee:
# - monitor.sh schreibt bei jedem Durchlauf die Datei:
#       /tmp/system_monitor_heartbeat
# - Dieses Skript wird vom Docker-Healthcheck aufgerufen.
# - Ist die Datei vorhanden und in den letzten 2 Minuten geändert worden,
#   gilt der Container als gesund (exit 0).
# - Andernfalls wird exit 1 zurückgegeben und der Container als "unhealthy"
#   eingestuft.

set -Eeuo pipefail

HB_FILE="/tmp/system_monitor_heartbeat"

if [ -f "$HB_FILE" ] && find "$HB_FILE" -mmin -2 -print -quit | grep -q .; then
  exit 0
else
  exit 1
fi
