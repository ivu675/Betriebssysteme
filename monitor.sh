#!/usr/bin/env bash
set -Eeuo pipefail

# KONFIGURATION & INITIALISIERUNG
# Was:   Definition von Variablen mit Default-Werten (Syntax ${VAR:-Default}).
# Wozu:  Ermöglicht Konfiguration von außen über Umgebungsvariablen (ENV).
# Warum: Container-Best-Practice (12-Factor App). Werte müssen via Docker Compose injizierbar sein,
#        ohne das Skript zu ändern. [cite_start]Fallbacks garantieren Lauffähigkeit auch ohne Config. [cite: 153, 154, 155]

INTERVAL="${INTERVAL:-60}"
LOG_FILE="${LOG_FILE:-/data/system_monitor.log}"
HOST_PROC="${HOST_PROC:-/host_proc}"
HOST_SYS="${HOST_SYS:-/host_sys}"
HOST_ROOT="${HOST_ROOT:-/host_root}"
DB_ENABLED="${DB_ENABLED:-true}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-monitor}"
DB_USER="${DB_USER:-monitor}"
DB_PASSWORD="${DB_PASSWORD:-monitor}"
RUN_ONCE=false

usage() {
  cat <<'EOF'
System Monitor

Usage: monitor.sh [options]

Options:
  -i, --interval <seconds>   Messintervall (>=1)
  -l, --log-file <path>      Logdatei ("-" für stdout)
      --db-host <host>       Datenbank-Host
      --db-port <port>       Datenbank-Port
      --db-name <name>       Datenbank-Name
      --db-user <user>       Datenbank-Benutzer
      --db-password <pw>     Datenbank-Passwort
      --no-db                Deaktiviert DB-Schreibvorgänge
      --once                 Nur eine Messung ausführen
  -h, --help                 Hilfe anzeigen
EOF
}

err_exit() {
  echo "ERROR: $1" >&2
  exit "${2:-1}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interval)
      [[ -n "${2:-}" ]] || err_exit "--interval benötigt einen Wert" 64
      INTERVAL="$2"
      shift 2
      ;;
    -l|--log-file)
      [[ -n "${2:-}" ]] || err_exit "--log-file benötigt einen Pfad" 64
      LOG_FILE="$2"
      shift 2
      ;;
    --db-host)
      [[ -n "${2:-}" ]] || err_exit "--db-host benötigt einen Wert" 64
      DB_HOST="$2"
      shift 2
      ;;
    --db-port)
      [[ -n "${2:-}" ]] || err_exit "--db-port benötigt einen Wert" 64
      DB_PORT="$2"
      shift 2
      ;;
    --db-name)
      [[ -n "${2:-}" ]] || err_exit "--db-name benötigt einen Wert" 64
      DB_NAME="$2"
      shift 2
      ;;
    --db-user)
      [[ -n "${2:-}" ]] || err_exit "--db-user benötigt einen Wert" 64
      DB_USER="$2"
      shift 2
      ;;
    --db-password)
      [[ -n "${2:-}" ]] || err_exit "--db-password benötigt einen Wert" 64
      DB_PASSWORD="$2"
      shift 2
      ;;
    --no-db)
      DB_ENABLED="false"
      shift
      ;;
    --once)
      RUN_ONCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      usage >&2
      err_exit "Unbekannte Option: $1" 64
      ;;
    *)
      usage >&2
      err_exit "Unerwartetes Argument: $1" 64
      ;;
  esac
done

if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]] || [ "$INTERVAL" -lt 1 ]; then
  err_exit "Intervall muss eine positive Ganzzahl sein" 65
fi

if ! [[ "$DB_PORT" =~ ^[0-9]+$ ]] || [ "$DB_PORT" -lt 1 ]; then
  err_exit "DB-Port muss eine positive Ganzzahl sein" 66
fi

if [[ "$LOG_FILE" == "-" ]]; then
  LOG_FILE="/dev/stdout"
else
  mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || err_exit "Log-Verzeichnis konnte nicht erstellt werden"
fi

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

# METHODE: cpu_usage
# Was:   Liest /host_proc/stat, wartet kurz (sleep 1), liest erneut und berechnet das Delta.
# Wozu:  Ermittlung der aktuellen CPU-Auslastung in Prozent.
# Warum: 1. Linux /proc/stat liefert kumulierte Ticks seit Boot -> Last ist immer eine Differenz über Zeit.
#        2. Zugriff auf /host_proc (Mount) statt /proc, um die echte Host-CPU zu messen, nicht nur den Container.
#        [cite_start]3. awk wird für Fließkomma-Berechnung genutzt, da Bash nur Integer kann. [cite: 180, 181]

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

# METHODE: mem_usage
# Was:   Parst 'MemTotal' und 'MemAvailable' aus /host_proc/meminfo.
# Wozu:  Berechnung des prozentual belegten Arbeitsspeichers.
# Warum: 'MemAvailable' ist präziser als 'MemFree', da es Caches berücksichtigt, die bei Bedarf frei werden.
#        [cite_start]Direktes Parsing im Stream spart Ressourcen. [cite: 181, 182]

mem_usage() {
  awk '
    $1=="MemTotal:"     {t=$2}
    $1=="MemAvailable:" {a=$2}
    END { if (t>0) printf "%.2f", (t-a)*100.0/t; else printf "0.00"; }
  ' "${HOST_PROC}/meminfo"
}

# METHODE: disk_usage
# Was:   Führt 'df -h' auf dem gemounteten Host-Root-Verzeichnis aus.
# Wozu:  Ermittlung des Füllstands der Festplatte.
# Warum: Zugriff muss auf /host_root erfolgen. Ein einfaches 'df /' würde nur das Overlay-FS
#        [cite_start]des Containers messen, was für Host-Monitoring nutzlos wäre. [cite: 182]

disk_usage() {
  pct="$(df -h "${HOST_ROOT}" 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  [ -z "$pct" ] && pct="$(df -h "${HOST_ROOT}/." 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  [ -z "$pct" ] && pct="$(df -h / 2>/dev/null | awk 'NR>1 {print $5; exit}')"
  printf "%s" "$pct"
}

# METHODE: send_to_db
# Was:   Erstellt einen SQL-String und sendet ihn via 'psql' an die Datenbank.
# Wozu:  Persistente Speicherung der Messwerte (Advanced-Anforderung).
# Warum: Nutzung von 'postgresql-client' (Alpine Paket) statt schwerer ORM-Bibliotheken hält das Image klein.
#        [cite_start]Manuelles Escaping der Hostnamen verhindert simple SQL-Injection-Fehler. [cite: 182, 183, 184, 185]

send_to_db() {
  if [[ "${DB_ENABLED,,}" != "true" ]]; then
    return 0
  fi

  local ts="$1" host="$2" cpu="$3" mem="$4" disk="$5"
  local escaped_host="${host//\'/\'\'}"
  local sql="\
    CREATE TABLE IF NOT EXISTS metrics (
      id SERIAL PRIMARY KEY,
      recorded_at TIMESTAMPTZ NOT NULL,
      hostname TEXT NOT NULL,
      cpu_usage NUMERIC(5,2) NOT NULL,
      mem_usage NUMERIC(5,2) NOT NULL,
      disk_usage NUMERIC(5,2) NOT NULL
    );
    INSERT INTO metrics (recorded_at, hostname, cpu_usage, mem_usage, disk_usage)
    VALUES ('${ts}'::timestamptz, '${escaped_host}', ${cpu}, ${mem}, ${disk});
  "

  if ! PGPASSWORD="$DB_PASSWORD" psql \
    --host="$DB_HOST" \
    --port="$DB_PORT" \
    --username="$DB_USER" \
    --dbname="$DB_NAME" \
    --command "$sql" >/dev/null 2>&1; then
    echo "WARN: Schreiben in die Datenbank fehlgeschlagen" >&2
  fi
}

# METHODE: log_once
# Was:   Sammelt alle Werte, schreibt Log, triggert DB-Export und aktualisiert Heartbeat.
# Wozu:  Zentrale Steuerfunktion für einen einzelnen Messzyklus.
# Warum: Erfüllt Basic (Log-Datei) und Advanced (DB) gleichzeitig.
#        [cite_start]Erzeugt '/tmp/system_monitor_heartbeat', damit der Healthcheck weiß, dass der Loop noch lebt. [cite: 186, 187]

log_once() {
  local ts host cpu mem disk disk_clean
  ts="$(timestamp)"
  host="$(hostname)"
  cpu="$(cpu_usage)"
  mem="$(mem_usage)"
  disk="$(disk_usage)"
  disk_clean="${disk//%/}"
  [ -z "$disk_clean" ] && disk_clean="0"

  {
    echo "Systemueberwachungsbericht - ${ts} (${host})"
    echo "----------------------------------------------"
    echo "CPU-Nutzung:        ${cpu}%"
    echo "Speichernutzung:    ${mem}%"
    echo "Datentraegernutzung: ${disk}"
    echo
  } | tee -a "$LOG_FILE"

  send_to_db "$ts" "$host" "$cpu" "$mem" "$disk_clean"

  touch /tmp/system_monitor_heartbeat || true
}

while true; do
  if ! log_once; then
    err_exit "Messung fehlgeschlagen" 70
  fi
  if [ "$RUN_ONCE" = true ]; then
    break
  fi
  sleep "$INTERVAL"
done
