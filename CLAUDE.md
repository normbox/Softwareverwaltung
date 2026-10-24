# CLAUDE.md

Open-Source-Werkzeug für Windows: installierte Software inventarisieren, neue Versionen und Sicherheitslücken finden, per Klick aktualisieren oder deinstallieren, mit KI-Berater. Das vollständige Konzept steht in `docs/KONZEPT.md`; lies es vor größeren Änderungen.

## Zusammenarbeit

- Antworte auf Deutsch. Code, Bezeichner und Commit-Messages auf Englisch, Kommentare und Doku für Nutzer auf Deutsch.
- Bei Mehrdeutigkeit kurz nachfragen statt raten.
- Pflegeaufwand gering halten: neue Abhängigkeiten nur mit Begründung, Langzeitversionen bevorzugen.

## Architektur (verbindlich)

- **Kern = PowerShell-Modul.** Alle Logik (Inventar, Versionsabgleich, Sicherheitsprüfung, Aktionen) liegt im Modul und muss ohne Oberfläche lauffähig und testbar sein.
- **Oberfläche = .NET 10 WPF** mit Fluent-Design (WPF-UI). Die App ruft das Modul über die eingebettete PowerShell-Engine (`Microsoft.PowerShell.SDK`) auf und enthält selbst keine Fachlogik.
- **KI-Berater** nutzt die Modulfunktionen als Tools. Zwei austauschbare LLM-Provider: Claude API und Ollama.
- Nur Windows 10/11; keine Linux-Kompatibilität einbauen.
- **Keine Zusatzinstallation für Endbenutzer.** Die WPF-App wird self-contained veröffentlicht (.NET-Laufzeit enthalten). PowerShell läuft eingebettet über Microsoft.PowerShell.SDK; ein separat installiertes PowerShell 7 darf nicht vorausgesetzt werden. PowerShell 7 wird nur zum Entwickeln und Testen gebraucht.
- Schwerpunkt Sicherheit + KI. Keine eigene Paketverwaltung nachbauen: Updates und Deinstallation über winget (Fallback Registry/msiexec/Appx).

## Sicherheitsprinzipien

- Die KI darf Updates und Deinstallationen nur **vorschlagen**; ausgeführt wird erst nach Bestätigung im UI.
- App läuft als normaler Benutzer; Administratorrechte (UAC) nur für die einzelne Aktion anfordern.
- Jede Aktion wird protokolliert.
- Vor dem Senden an Cloud-Modelle Benutzername, Rechnername und Benutzerpfade entfernen.
- API-Schlüssel (Anthropic, NVD, GitHub) nie ins Repository; über Windows-Anmeldeinformationsverwaltung oder Umgebungsvariablen.
- Ergebnisse aus Web-Recherche als „unbestätigt“ kennzeichnen.

## Git-Arbeitsweise

- `main` bleibt stabil: kein direktes Arbeiten auf `main`.
- Ein Branch pro Etappe, benannt nach dem Muster `etappe-<nr>-<thema>` (z. B. `etappe-1-inventar`).
- Nach jedem fertigen, lauffähigen Teilschritt committen (kleine Commits, Message auf Englisch).
- Ist die Etappe fertig, per Pull Request auf GitHub in `main` mergen.

## Fahrplan

Etappenweise vorgehen, siehe `docs/KONZEPT.md` Abschnitt „Fahrplan“. Aktuell: Etappe 1, Inventar-Modul.
