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

# HEALTHCHECK-LOGIK
# Was:   Prüft: Existiert die Heartbeat-Datei UND ist sie jünger als 2 Minuten? (-mmin -2)
# Wozu:  Sicherstellen, dass der Monitor-Loop aktiv ist und nicht hängt.
# Warum: Ein reiner Prozess-Check (ps) reicht nicht, da der Prozess in einem Deadlock hängen könnte.
#        [cite_start]Nur eine aktualisierte Datei beweist, dass 'log_once' wirklich ausgeführt wird. [cite: 97, 98, 100, 102]

if [ -f "$HB_FILE" ] && find "$HB_FILE" -mmin -2 -print -quit | grep -q .; then
  exit 0
else
  exit 1
fi
