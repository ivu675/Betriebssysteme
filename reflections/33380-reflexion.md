#Betriebssysteme - Reflexion Projekt Tim David (Matr.-Nr. 33380)

##Einleitung
Das Projekt „Dashboard für Systeminformationen“ hatte das Ziel eine containerisiertes Tool zur Erfassung, Speicherung und Visualisierung von Systemmetriken wie CPU, Disk und RAM Auslastung. Während der Projektphase lag mein Fokus hauptsächlich auf dem sicherstellen der Systemstabilität durch Healthchecks, der erweiterte Visualisierung in Grafana und die Qualitätssicherung. Die folgende Reflexion ordnet die praktische Umsetzung unseres Projekts in die theoretischen Konzepte, wie Prozesse und Threads, Scheduling oder Containerisierung, aus den Vorlesungen ein.


##Einordnung in die Vorlesung
*Prozesse & Threads*
Die Arbeit am Hauptskript monitor.sh verdeutlichte Konzepte der Prozessverwaltung. Das Laufzeitverhalten des Skripts lässt sich mit dem 3-State-Model aus der Vorlesung erklären. Wenn das Skript aktiv Befehle ausführt, um Daten aus `/proc` zu lesen, befindet es sich im Zustand Running. Unmittelbar nach der Datenerfassung ruft der Code den Befehl sleep `$INTERVAL` auf, wodurch der Prozess für den Großteil seiner Lebensdauer in den Zustand Blocked wechselt und auf das Timer-Event wartet. Sobald die 60 Sekunden abgelaufen sind, versetzt der Scheduler den Prozess zurück in den Zustand Ready, bis ihm erneut CPU-Zeit zugewiesen wird. Die Synchronisation zwischen dem monitor.sh-Prozess und dem überwachenden healthcheck.sh erfolgt über die geteilte Datei `/tmp/system_monitor_heartbeat` im Dateisystem. Was die Interprozesskommunikation zum praktischen Einsatz brachte.

*Scheduling* 
Unser Container wird vom Hostsystem als normaler Prozess verwaltet und konkurriert daher mit anderen Prozessen um Rechenzeit. Bei hoher Systemauslastung kann es deshalb sein, dass der Monitor.sh später Rechenzeit bekommt als im Intervall angegeben. Bei einem Intervall von 60 Sekunden und einem Healthcheck-Intervall von 120 Sekunden kann das bei größeren Prozessen, wie Builds, dazu führen, dass der Monitor.sh vom Healthcheck als unhealthy markiert wird. Wodurch der Container fälschlicherweise als defekt markiert würde. Das zeigt das Rechenzeit in festen Intervallen, je nach Auslastung nicht garantiert sind.

*Dateisysteme*
Wir benutzen das Virtual File System von Linux um auf Systemdateien zuzugreifen. Wir lesen im monitor.sh einfach Textdateien aus den gemounteten Verzeichnissen `/proc` und `/sys`. Ein wichtiger Punkt waren dabei die User Access Rights. Im Skript healthcheck.sh prüfen wir mittels find `"$HB_FILE" -mmin -2` den Zeitstempel der Heartbeat-Datei. Damit dies funktioniert, musste sichergestellt werden, dass der User app im Container Schreibrechte auf das Verzeichnis `/tmp` besitzt.

*Visualisierung und Containerisierung*
Kern des Projekts ist die Isolation der einzelnen Hauptprozesse, wie Monitoring, Datenbank oder Grafana, in Container die sich ein Host-System teilen. Während Docker normalerweise Prozesse isoliert, mussten wir diese Isolation für das Monitoring umgehen. Dies setzten wir im docker-compose.yml durch Bind-Mounts um, indem wir `/proc` des Hosts als `/host_proc` in den Container einbinden. So greift der Prozess auf die Daten des Hostsystems zu, anstatt nur seinen eigenen isolierten Namensraum zu sehen. 


##Meine Architekturentscheidungen und Implementierung
*Abbruch bei Fehler*
In allen Skripten, wie etwa monitor.sh, bewirke ich durch den Befehl `set -Eeuo pipefail` eine feste Fehlerbehandlung. Diese Zeile bewirkt, dass das Skript sofort abbricht, wenn ein Befehl fehlschlägt, eine Variable nicht gesetzt ist oder ein Fehler in einer Pipe auftritt. Dies verhindert das potenziell inkonsistente Daten produziert werden.

*Flexibles Dashboard*
Im Advanced-Teil habe ich mich um die Flexibilität des Grafana-Dashboards gekümmert, wie in den Anforderungen vorgeschrieben. In der Dashboard-Definition system-metrics.json implementierte ich Template-Variablen für den Hostnamen. Die SQL-Abfrage W`HERE ... AND ('${Host:raw}'='__all' OR hostname='${Host:raw}')` ermöglicht es dem Nutzer, zwischen der Ansicht aller Server oder eines spezifischen Hosts zu wechseln. Dies macht das Dashboard skalierbar für Umgebungen mit mehreren überwachten Systemen.


##Beobachtete Effekte und Optimierungen
*Race-Conditions*
Beim Healthcheck kam es anfangs zu Fehlalarmen beim Container-Start, da die Heartbeat-Datei in den ersten Sekunden noch nicht existierte. Ich lösten dies im Code von healthcheck.sh, indem ich vor der Zeitprüfung mit `[ -f "$HB_FILE" ]` sicherstellte, dass die Datei existiert, um Fehlermeldungen von find zu vermeiden.

*Grafana* 
Visuell zeigte sich in Grafana, dass fehlende Datenpunkte standardmäßig fortgeführt wurden, was bei einem Absturz des monitor.sh-Skripts fälschlicherweise konstante Werte nahelegt. Durch die Konfiguration im Dashboard, Null-Werte nicht zu verbinden, konnten wir Systemausfälle transparent als Lücken im Graphen sichtbar machen.


##Fazit 
Zusammenfassend hat mir das Projekt gezeigt, dass die Entwicklung von Systemtools ein tiefes Verständnis von Betriebssystem-Konzepten erfordert. Die theoretischen Grundlagen, insbesondere das 3-State-Model für das Prozessverständnis und das Wissen über Dateisystem-Metadaten für den Healthcheck, waren notwendig, um eine funktionsfähige Lösung zu entwickeln. Besonders die praktische Arbeit an der Schnittstelle zwischen Container-Isolation und Host-Zugriff verdeutlichte die Funktionsweise von Virtualisierungstechniken.
