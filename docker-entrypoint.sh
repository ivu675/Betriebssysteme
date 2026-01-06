#!/usr/bin/env sh
set -eu

chown -R app:app /data /tmp 2>/dev/null || true

exec su-exec app "$@"
