#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="${LOG_FILE:-/data/system_monitor.log}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-monitor}"
DB_USER="${DB_USER:-monitor}"
DB_PASSWORD="${DB_PASSWORD:-monitor}"

usage() {
  cat <<'EOF'
monitorctl - Werkzeug zur Auswertung der Systemmetriken

Kommandos:
  stream [--lines N] [--no-follow]   Zeigt Logeinträge in Echtzeit (Standard: Follow)
  query  [Filteroptionen]            Fragt die metrics-Tabelle in PostgreSQL ab
  help                               Zeigt diese Hilfe

Filteroptionen für query:
  --host <name>          Filtert nach Hostname
  --since <timestamp>    ISO-Timestamp (z. B. "2025-01-07 10:00")
  --until <timestamp>    ISO-Timestamp
  --metric <cpu|mem|disk> Kennzahl für Min/Max-Filter (Default: cpu)
  --min <value>          Untergrenze für Kennzahl
  --max <value>          Obergrenze für Kennzahl
  --limit <n>            Anzahl Ergebnisse (Default: 50)
  --order <asc|desc>     Sortierung nach recorded_at (Default: desc)
  --format <table|csv|json> Ausgabeformat (Default: table)

Beispiele:
  monitorctl stream --lines 5
  monitorctl query --host alpha --since "2025-01-07 08:00" --metric mem --max 70
EOF
}

err_exit() {
  echo "ERROR: $1" >&2
  exit "${2:-1}"
}

command="${1:-}"
if [ -z "$command" ]; then
  usage >&2
  exit 64
fi
shift

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

run_psql() {
  local format="$1"
  shift
  local psql_args=(
    --host="$DB_HOST"
    --port="$DB_PORT"
    --username="$DB_USER"
    --dbname="$DB_NAME"
    --no-psqlrc
    --set=ON_ERROR_STOP=1
    --pset=footer=off
  )
  case "$format" in
    csv)
      psql_args+=(--csv)
      ;;
    json)
      psql_args+=(--pset=format=json --pset=tuples_only=on)
      ;;
    table|*)
      psql_args+=(--pset=format=aligned)
      ;;
  esac
  PGPASSWORD="$DB_PASSWORD" psql "${psql_args[@]}" --command "$*"
}

case "$command" in
  help|-h|--help)
    usage
    exit 0
    ;;
  stream)
    lines=20
    follow=true
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -n|--lines)
          [[ -n "${2:-}" ]] || err_exit "--lines benötigt einen Wert" 64
          lines="$2"
          shift 2
          ;;
        --no-follow)
          follow=false
          shift
          ;;
        -h|--help)
          echo "Usage: monitorctl stream [--lines N] [--no-follow]" >&2
          exit 0
          ;;
        *)
          err_exit "Unbekannte Option für stream: $1" 64
          ;;
      esac
    done
    [[ -f "$LOG_FILE" ]] || touch "$LOG_FILE"
    if ! [[ "$lines" =~ ^[0-9]+$ ]]; then
      err_exit "lines muss numerisch sein" 65
    fi
    if [ "$follow" = true ]; then
      tail -n "$lines" -f "$LOG_FILE"
    else
      tail -n "$lines" "$LOG_FILE"
    fi
    ;;
  query)
    host=""
    since=""
    until=""
    metric="cpu"
    min_val=""
    max_val=""
    limit=50
    order="desc"
    format="table"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --host)
          host="${2:-}"
          shift 2
          ;;
        --since)
          since="${2:-}"
          shift 2
          ;;
        --until)
          until="${2:-}"
          shift 2
          ;;
        --metric)
          metric="${2:-}"
          shift 2
          ;;
        --min)
          min_val="${2:-}"
          shift 2
          ;;
        --max)
          max_val="${2:-}"
          shift 2
          ;;
        --limit)
          limit="${2:-}"
          shift 2
          ;;
        --order)
          order="${2:-}"
          shift 2
          ;;
        --format)
          format="${2:-}"
          shift 2
          ;;
        -h|--help)
          echo "Usage: monitorctl query [--host NAME] [--since TS] [--until TS] [--metric cpu|mem|disk] [--min N] [--max N] [--limit N] [--order asc|desc] [--format table|csv|json]" >&2
          exit 0
          ;;
        *)
          err_exit "Unbekannte Option für query: $1" 64
          ;;
      esac
    done

    case "$metric" in
      cpu) metric_col="cpu_usage" ;;
      mem) metric_col="mem_usage" ;;
      disk) metric_col="disk_usage" ;;
      *) err_exit "Ungültige Kennzahl: $metric" 65 ;;
    esac

    if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -le 0 ]; then
      err_exit "Limit muss > 0 sein" 66
    fi

    case "$order" in
      asc|desc) ;;
      *) err_exit "Order muss asc oder desc sein" 67 ;;
    esac

    case "$format" in
      table|csv|json) ;;
      *) err_exit "Format muss table, csv oder json sein" 68 ;;
    esac

    sql="SELECT recorded_at, hostname, cpu_usage, mem_usage, disk_usage FROM metrics WHERE 1=1"
    if [ -n "$host" ]; then
      sql+=" AND hostname='$(sql_escape "$host")'"
    fi
    if [ -n "$since" ]; then
      sql+=" AND recorded_at >= '$since'::timestamptz"
    fi
    if [ -n "$until" ]; then
      sql+=" AND recorded_at <= '$until'::timestamptz"
    fi
    if [ -n "$min_val" ]; then
      sql+=" AND $metric_col >= $min_val"
    fi
    if [ -n "$max_val" ]; then
      sql+=" AND $metric_col <= $max_val"
    fi
    sql+=" ORDER BY recorded_at $order LIMIT $limit;"
    run_psql "$format" "$sql"
    ;;
  *)
    usage >&2
    err_exit "Unbekanntes Kommando: $command" 64
    ;;
esac
