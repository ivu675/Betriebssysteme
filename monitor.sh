#!/usr/bin/env bash
# author: <dein Name>       version: 1.0
#
# Einfaches System-Monitoring-Skript, gedacht für den Einsatz in einem Container.
# Liest CPU-, Speicher- und Plattenauslastung vom Host aus und schreibt regelmäßig
# einen kleinen Bericht ins Log.
#
# - INTERVAL:    Abstand zwischen zwei Messungen (Sekunden).
# - LOG_FILE:    Wohin geschrieben wird (Standard: stdout).
# - HOST_PROC:   Pfad zum /proc des Hosts (wird vom Container hineingemountet).
# - HOST_SYS:    Reserve für /sys vom Host (aktuell nicht genutzt).
# - HOST_ROOT:   Wurzelverzeichnis des Host-Dateisystems (für df).
#
# Ablauf in Kurzform:
# - cpu_usage():   Liest zweimal /proc/stat und berechnet daraus die CPU-Auslastung.
# - mem_usage():   Nutzt MemTotal und MemAvailable aus /proc/meminfo und berechnet
#                  die Speicherbelegung in Prozent.
# - disk_usage():  Fragt per df die Belegung des gemounteten Host-Root-Dateisystems ab.
# - log_once():    Baut einen kleinen Textbericht zusammen und hängt ihn an LOG_FILE an.
#                  Zusätzlich wird eine Heartbeat-Datei aktualisiert, die vom
#                  Healthcheck-Skript ausgewertet wird.
# - Hauptloop:     Ruft log_once in einer Endlosschleife auf und wartet jeweils INTERVAL Sekunden.

set -Eeuo pipefail

INTERVAL="${INTERVAL:-60}"                     # Sekunden zwischen Messungen
LOG_FILE="${LOG_FILE:-/dev/stdout}"            # Standard: stdout statt Datei
HOST_PROC="${HOST_PROC:-/host_proc}"
HOST_SYS="${HOST_SYS:-/host_sys}"
HOST_ROOT="${HOST_ROOT:-/host_root}"

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

cpu_usage() {
  read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 g1 gn1 < <(head -n1 "${HOST_PROC}/stat")
  sleep 1
  read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 g2 gn2 < <(head -n1 "${HOST_PROC}/stat")

  local idle1=$((i1 + w1))
  local idle2=$((i2 + w2))
  local nonidle1=$((u1 + n1 + s1 + irq1 + sirq1 + st1))
  local nonidle2=$((u2 + n2 + s2 + irq2 + sirq2 + st2))
  local total1=$((idle1 + nonidle1))
  local total2=$((idle2 + nonidle2))
  local totald=$((total2 - total1))
  local idled=$((idle2 - idle1))

  if [ "$totald" -le 0 ]; then
    printf "0.00"
    return
  fi
  awk -v td="$totald" -v id="$idled" 'BEGIN { printf "%.2f", (td - id) * 100.0 / td }'
}

mem_usage() {
  awk '
    $1=="MemTotal:"     {t=$2}
    $1=="MemAvailable:" {a=$2}
    END { if (t>0) printf "%.2f", (t-a)*100.0/t; else printf "0.00"; }
  ' "${HOST_PROC}/meminfo"
}

disk_usage() {
  pct="$(df -h "${HOST_ROOT}" 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  [ -z "$pct" ] && pct="$(df -h "${HOST_ROOT}/." 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  [ -z "$pct" ] && pct="$(df -h / 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  printf "%s" "$pct"
}

log_once() {
  local ts host cpu mem disk
  ts="$(date "+%Y-%m-%d %H:%M:%S")"
  host="$(hostname)"
  cpu="$(cpu_usage)"
  mem="$(mem_usage)"
  disk="$(disk_usage)"

  {
    echo "Systemüberwachungsbericht - ${ts} (${host})"
    echo "----------------------------------------------"
    echo "CPU-Nutzung:        ${cpu}%"
    echo "Speichernutzung:    ${mem}%"
    echo "Datenträgernutzung: ${disk}"
    echo
  } >> "$LOG_FILE"

  # Heartbeat für Healthcheck – unabhängig vom Log-Ziel
  touch /tmp/system_monitor_heartbeat || true
}

# Hauptloop
while true; do
  log_once
  sleep "$INTERVAL"
done
