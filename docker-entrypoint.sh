#!/usr/bin/env sh
set -eu

# RECHTE-KORREKTUR
# Was:   Ändert den Besitzer von /data rekursiv auf den User 'app'.
# Wozu:  Fixen von Berechtigungsproblemen bei Host-Bind-Mounts.
# Warum: Docker Bind-Mounts gehören oft 'root' auf dem Host. Der Container-User 'app' darf
#        dort sonst nicht schreiben. [cite_start]Skript läuft als root an, fixt Rechte und wechselt dann zu 'app'. [cite: 245]

chown -R app:app /data /tmp 2>/dev/null || true

exec su-exec app "$@"
