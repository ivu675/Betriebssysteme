#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/4] Prüfe Bash-Syntax"
for file in monitor.sh healthcheck.sh monitorctl.sh; do
  bash -n "$ROOT_DIR/$file"
done

echo "[2/4] Starte Monitor in der lokalen Umgebung (no-db, once)"
HOST_PROC=/proc \
HOST_SYS=/sys \
HOST_ROOT=/ \
LOG_FILE=- \
DB_ENABLED=false \
INTERVAL=1 \
  bash "$ROOT_DIR/monitor.sh" --once --no-db --interval 1 --log-file - >/dev/null

echo "[3/4] Prüfe monitorctl help"
bash "$ROOT_DIR/monitorctl.sh" help >/dev/null

echo "[4/4] Prüfe monitorctl stream ohne Follow"
tmp_log="$ROOT_DIR/logs/test_smoke.log"
mkdir -p "$(dirname "$tmp_log")"
echo "SmokeTest $(date)" >"$tmp_log"
LOG_FILE="$tmp_log" bash "$ROOT_DIR/monitorctl.sh" stream --lines 1 --no-follow >/dev/null
rm -f "$tmp_log"

echo "Smoke-Tests erfolgreich."
