# System Monitor + PostgreSQL + Grafana

Leichtgewichtiger Stack zur Hostüberwachung: Ein Bash-Agent (Docker-Container) liest zyklisch CPU-, RAM- und Datenträgerwerte direkt aus den Host-Mounts, speichert sie strukturiert in PostgreSQL und stellt die Zeitreihen in Grafana bereit. Dokumentation, Tests und Zusatztools stellen sicher, dass die Abgabeanforderungen der Veranstaltung „Operating Systems & Distributed Systems“ erfüllt werden.

---

## Projektziele & Umfang
- **Basic-Anteil**: funktionierender Monitor, der alle 60 s Messwerte vom Host sammelt, formatierte Logs schreibt und containerisiert läuft.
- **Advanced-Anteil**: Echtzeit-Streaming (`monitorctl stream`), Such- und Filterfunktionen über CLI + Grafana-Template-Variablen, persistente Speicherung in PostgreSQL sowie visualisierte Dashboards in einem separaten Web-Container.
- **Betriebsmodell**: Fokus auf Docker/Docker-Compose (kein Kubernetes erforderlich, aber Compose-Setup ist reproduzierbar). Optional lassen sich weitere Targets anbinden.

## Architektur & Datenfluss
```
+------------------+      INSERT (metrics)      +----------------------+      SQL Datasource      +----------------+
| monitor (Bash)   | -------------------------> | PostgreSQL (db)      | <---------------------- | Grafana OSS    |
|  - monitor.sh    |                            |  metrics table       |                        | Dashboard      |
|  - monitorctl.sh | <--------- tail/log -------|  db-data volume      |                        | Host-Filter    |
+------------------+         logs volume        +----------------------+                        +----------------+
        | 60s Loop
        v
 logs/system_monitor.log  (auch via monitorctl stream)
```
- **Netzwerk**: Alle Services laufen im Compose-Netzwerk; Credentials werden via ENV übergeben.
- **Mounts**: `/proc`, `/sys`, `/` werden read-only in den Monitor injiziert, damit er Host-Werte statt Container-internen Sicht liest; `/data` ist ein bind mount auf `./logs`.

## Komponentenübersicht
| Komponente | Art | Beschreibung | Artefakte |
| --- | --- | --- | --- |
| monitor | Bash + Alpine Container (Non-Root `app`) | Liest Hostmetriken, schreibt Logs & DB, bietet CLI für Streaming/Queries | `Dockerfile`, `docker-entrypoint.sh`, `monitor.sh`, `monitorctl.sh`, `healthcheck.sh` |
| db | PostgreSQL 16 | Persistente Ablage der Messwerte, Healthcheck via `pg_isready` | `docker-compose.yml` |
| grafana | Grafana OSS 11.3 | Visualisiert CPU/RAM/Disk, Host-Filter via Template-Variable, Refresh 5 s | `grafana/provisioning/...` |
| docs/tests | Markdown + Bash | README, Web-Dokumentation (`index.html`), Smoke-Tests, Reflexionsvorlagen | `README.md`, `index.html`, `tests/smoke.sh`, `reflections/` |

## Softwarestände & Anforderungen
Alle Abhängigkeiten sind in `requirements.txt` hinterlegt:
```
cat requirements.txt
```
Wichtigste Versionen: Bash ≥ 5.1, Docker ≥ 24.x, Docker Compose ≥ 2.21, PostgreSQL-Client ≥ 16, Grafana OSS 11.3.0. Für lokale Tests wird ein Linux-artiges System mit Zugriff auf `/proc`/`/sys` empfohlen.

## Build- & Run-Anweisungen
### 1. Lokal ohne Container (funktionale Tests)
```bash
HOST_PROC=/proc HOST_SYS=/sys HOST_ROOT=/ LOG_FILE=- DB_ENABLED=false \
  ./monitor.sh --once --interval 1 --no-db --log-file -
```
Ausgabe erscheint auf STDOUT; Exit-Codes ≥ 64 signalisieren Param-Fehler.

### 2. Docker-Image bauen
```bash
docker build -t team_2_06-monitor .
```
Image enthält nur Bash + `postgresql-client` und läuft als Non-Root.

### 3. Compose-Stack
```bash
docker compose up -d --build
watch docker compose ps
```
- Logs prüfen: `docker compose logs -f monitor`
- Echtzeit-Streaming: `docker compose exec monitor /app/monitorctl.sh stream`
- Grafana: `http://localhost:3000` (Login `admin` / `change-me-now`, danach Passwort setzen)
- Stack stoppen: `docker compose down` (mit `-v`, um Volumes zu leeren)

## Konfiguration
### Umgebungsvariablen (Monitor)
| Variable | Default | Beschreibung |
| --- | --- | --- |
| `INTERVAL` | `60` | Messintervall in Sekunden (muss ≥ 1 sein) |
| `LOG_FILE` | `/data/system_monitor.log` | Persistente Log-Datei (Bind-Mount `./logs`) |
| `HOST_PROC`, `HOST_SYS`, `HOST_ROOT` | `/host_*` | Bind-Mounts auf Host-Dateisysteme (read-only) |
| `DB_ENABLED` | `true` | Schaltet Inserts in die DB ein/aus |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | siehe Compose | DB-Konnektivität |

Alle Werte lassen sich zusätzlich per CLI überschreiben, z. B. `./monitor.sh --interval 30 --log-file - --no-db`.

### Datenbank & Tabelle
`monitor.sh` erzeugt automatisch die Tabelle `metrics`:
```sql
CREATE TABLE IF NOT EXISTS metrics (
  id SERIAL PRIMARY KEY,
  recorded_at timestamptz NOT NULL,
  hostname text NOT NULL,
  cpu_usage numeric(5,2) NOT NULL,
  mem_usage numeric(5,2) NOT NULL,
  disk_usage numeric(5,2) NOT NULL
);
```
Manueller Blick in die Daten:
```bash
docker compose exec db psql -U monitor -d monitor -c "SELECT * FROM metrics ORDER BY recorded_at DESC LIMIT 5;"
```

## CLI-Werkzeuge & Such-/Filterfunktionen
### monitor.sh
```
Usage: monitor.sh [options]
  -i, --interval <seconds>
  -l, --log-file <path|->
      --db-host/--db-port/--db-name/--db-user/--db-password
      --no-db (keine Inserts)
      --once  (ein Messzyklus)
  -h, --help
```
- Exit-Codes: `0` (OK), `64–69` (Argument-/Validierungsfehler), `70` (Messung fehlgeschlagen).
- Legt `/tmp/system_monitor_heartbeat` für den Healthcheck an.

### monitorctl.sh
```
monitorctl stream [--lines N] [--no-follow]
monitorctl query  --host <name> --since <ts> --metric <cpu|mem|disk> --min <n> --format <table|csv|json> ...
```
Beispiele:
```bash
# Echtzeit-Logs mit Follow
docker compose exec monitor /app/monitorctl.sh stream

# Filter: Hosts mit RAM > 70% seit heute Morgen
docker compose exec monitor /app/monitorctl.sh \
  query --metric mem --min 70 --since "2025-01-07 08:00" --format table
```
Damit sind die geforderten Echtzeit-Updates sowie Such- und Filterfunktionen abgedeckt.

## Grafana-Dashboard
- Provisioniert via `grafana/provisioning/...`, Datasource `SystemMetrics` zeigt direkt auf PostgreSQL.
- Refresh-Intervall: 5 s (quasi Echtzeit).
- Host-Filter: Variable `Host` erlaubt Single-Select oder `Alle`.
- Panels: kombinierte Time-Series (CPU/RAM/Disk) + Tabelle der letzten Werte.

## Logging & Monitoring
- Persistente Log-Datei: `logs/system_monitor.log` (Host), Streaming via `monitorctl stream`.
  - Der Entrypoint chowned `/data` automatisch auf den Container-User, sodass keine manuellen chmod/chown-Schritte auf neuen Hosts nötig sind.
- Relevante Befehle für die Anforderung „Logs verfügbar machen“:
  - Host-Log ansehen: `tail -n 20 logs/system_monitor.log`
  - Live-Stream im Container: `docker compose exec monitor /app/monitorctl.sh stream --lines 20`
  - Container-STDOUT inklusive Warnungen: `docker compose logs -f monitor`
  - Strukturierte Historie (SQL): `docker compose exec db psql -U monitor -d monitor -c "SELECT recorded_at, hostname, cpu_usage, mem_usage, disk_usage FROM metrics ORDER BY recorded_at DESC LIMIT 20;"`
- Container-Healthcheck (`healthcheck.sh`) verwirft Container, wenn >2 min kein Heartbeat geschrieben wurde.
- Remote-Zugriff: Grafana auf Port 3000, CLI über `docker compose exec monitor ...` nutzbar.

## Tests & Qualitätssicherung
1. **Smoke-Tests**: `./tests/smoke.sh` validiert Bash-Syntax, startet den Monitor einmal lokal und testet `monitorctl`.
2. **Compose-E2E**: `docker compose up -d --build`, anschließend `docker compose ps`, `docker compose logs -f monitor`, Grafana prüfen.
3. **Formale Prüfung**: Code hält sich an `set -Eeuo pipefail`, modulare Funktionen, saubere Exit-Codes.

## Troubleshooting & bekannte Probleme
| Problem | Ursache | Lösung |
| --- | --- | --- |
| Keine Daten in DB | DB nicht erreichbar oder Credentials falsch | `docker compose logs monitor`, ENV prüfen, DB-Healthcheck abwarten |
| Grafana ohne Dashboard | Provisioning-Verzeichnis nicht gemountet | Compose-Volume `./grafana/provisioning` kontrollieren, Grafana neu starten |
| Log-Datei leer | Container hat keine Host-Mounts | Prüfen, ob `/proc`, `/sys`, `/` Bind-Mounts in Compose aktiv sind |
| Healthcheck schlägt fehl | Monitor Thread hängt | Container-Logs prüfen, ggf. Container neustarten (`docker compose restart monitor`) |

## Beitrags Matrix
| Studierende Person | Basic-Anteil | Advanced-Anteil / QA |
| --- | --- | --- |
| Malcolm-Mustapha Paul | Compose-Setup, Dockerfile-Basis, Initial-README | Log-Persistenz, Tests & Dokumentation, Grafana-Provisioning, Release-Vorbereitung |
| Tim-Niklas David | Healthcheck | Dashboard-Filter/Refresh, Query-Tool Reviews, Qualitätssicherung, monitor.sh |
| Christian Alexander Mertens | Bash-Agent Grundlogik, Datenbank-Anbindung | CLI-Erweiterungen, monitorctl.sh |



