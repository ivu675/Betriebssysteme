# Reflexion – Malcolm-Mustapha Paul, Matrikelnummer 33439

## Einordnung in die Vorlesung
**Prozesse & Threads:** Beim Arbeiten am Monitor habe ich deutlich gemerkt, wie wichtig ein sauberer Umgang mit Prozessen ist. Unser Bash-Skript läuft als einzelner Prozess im Container und ruft wiederholt kleine Hilfsprogramme wie `head`, `awk` oder `psql` auf. Wenn ich das Intervall verkürzt habe, liefen diese Subprozesse häufiger parallel, was sofort an der CPU-Last sichtbar wurde. Die Healthchecks wirken letztlich wie ein externer Prozess, der kontrolliert, ob der Hauptprozess noch lebt – ein gutes Beispiel für Prozessüberwachung aus der Vorlesung.

**Scheduling:** Die 60‑Sekunden-Schleife ist nur zuverlässig, wenn der Scheduler dem Container auch wirklich Zeit gibt. Auf meinem Laptop habe ich gesehen, dass Lastspitzen anderer Container die Messung verschieben können. Damit passt die Beobachtung aus der Vorlesung: Scheduling-Entscheidungen des Hosts haben direkte Auswirkungen auf Anwendungen – besonders, wenn sie in gleichmäßigen Takten laufen sollen.

**Speichermanagement:** Die Messungen greifen auf `/proc/meminfo` zu. Erst dadurch habe ich verstanden, wie sehr Linux den Arbeitsspeicher virtualisiert. Der Container selbst hat nur ein eigenes Limit, aber dank Read-only-Mount sehen wir die echten Host-Werte. Auch die Entscheidung, Strings nicht unnötig zu kopieren und Variablen nur mit `local` zu verwenden, stammt aus dem Bewusstsein, Speicher sparsam zu behandeln.

**Virtualisierung & Containerisierung:** Wir nutzen Container nicht nur zum Verpacken, sondern auch als Sicherheitsgrenze. Der Monitor läuft als Non-Root-User, die Host-Dateisysteme werden read-only gemountet und Grafana liegt als eigener Web-Container daneben. Damit habe ich praktisch erlebt, wie „leichtgewichtige“ Virtualisierung (Container) genau die Themen Isolation und reproduzierbare Laufzeitumgebungen aus der Vorlesung abbildet.

**Dateisysteme:** Die Bind-Mounts `/proc`, `/sys` und `/` sind allesamt Beispiele dafür, wie Dateisysteme in Linux nicht nur echte Platten repräsentieren, sondern auch Systeminformationen bereitstellen. Wir mussten lernen, dass Dateirechte zwischen Host und Container unterschiedlich interpretiert werden – daher der zusätzliche Entrypoint, der die Besitzrechte auf `/data` anpasst.

## Architekturentscheidungen
Der Stack besteht bewusst nur aus Bash, PostgreSQL und Grafana. Bash war vorgegeben und hat den Vorteil, dass wir direkt auf `/proc` zugreifen können, ohne zusätzliche Bibliotheken. PostgreSQL haben wir gewählt, weil SQL-Abfragen sofort Such- und Filterfunktionen ermöglichen; Grafana bringt das fertige Dashboard, ohne dass wir selbst einen Webserver schreiben müssen.



## Beobachtete Effekte & Optimierungen
- **Bottlenecks:** Der offensichtlichste Engpass war die Dateiberechtigung auf `/data`. Auf manchen Systemen gehörte das Volume nicht dem Container-User, sodass `monitorctl stream` nichts ausspuckte. Die Lösung mit dem Entrypoint, der `chown` übernimmt, zeigt, wie wichtig es ist, Dateisysteme aus Containersicht zu betrachten.
- **CPU-Spikes:** Beim Testen mit sehr kurzen Intervallen (z. B. 5 s) schoss die CPU-Nutzung hoch, weil `sleep` kaum noch zum Zug kam und `psql` fast permanent lief. Hier hätte ein asynchrones Design (z. B. Daten puffern und nur alle paar Iterationen schreiben) geholfen.
- **Verbesserungen:** Für eine nächste Version würde ich Logrotation einbauen und das Monitoring mit Alerts koppeln. Außerdem wäre eine REST- oder Websocket-Schicht spannend, um die Daten ohne Grafana konsumieren zu können. Trotzdem bin ich zufrieden, dass der jetzige Stand alle Veranstaltungsspezifikationen erfüllt und sich auf jedem Rechner mit `docker compose up -d --build` reproduzieren lässt.

> Fazit: Das Projekt hat viele Themen aus „Operating Systems & Distributed Systems“ greifbar gemacht. Besonders spannend war zu sehen, dass selbst einfache Bash-Skripte sofort in komplexe Betriebssystemthemen wie Prozesse, Scheduling und Dateisystemrechte hineinführen.
