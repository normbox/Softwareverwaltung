# CLAUDE.md

Open-Source-Werkzeug für Windows: installierte Software inventarisieren, neue Versionen und Sicherheitslücken finden, per Klick aktualisieren oder deinstallieren, mit KI-Berater. Das vollständige Konzept steht in `docs/KONZEPT.md`; lies es vor größeren Änderungen.

## Zusammenarbeit

- Antworte auf Deutsch. Code, Bezeichner und Commit-Messages auf Englisch, Kommentare und Doku für Nutzer auf Deutsch.
- Bei Mehrdeutigkeit kurz nachfragen statt raten.
- Pflegeaufwand gering halten: neue Abhängigkeiten nur mit Begründung, Langzeitversionen bevorzugen.

## Architektur (verbindlich)

- **Kern = PowerShell-Modul.** Alle Logik (Inventar, Versionsabgleich, Sicherheitsprüfung, Aktionen) liegt im Modul und muss ohne Oberfläche lauffähig und testbar sein.
- **Oberfläche = .NET 10 WPF** mit Fluent-Design (WPF-UI). Die App ruft das Modul über die eingebettete PowerShell-Engine (`Microsoft.PowerShell.SDK`) auf und enthält selbst keine Fachlogik.
- **KI-Berater** nutzt die Modulfunktionen als Tools (`Get-AdvisorTool`, `Invoke-AdvisorTool`). Vorerst nur lokale Modelle über die OpenAI-kompatible Schnittstelle (Vorgaben: Ollama, LM Studio, Unsloth Studio, eigene Adresse; kein Standardmodell). Die App hat eine Anbieter-Schnittstelle; externe Anbieter (z. B. Claude API) kommen später als Plugin, ohne Umbau.
- Nur Windows 10/11; keine Linux-Kompatibilität einbauen.
- **Keine Zusatzinstallation für Endbenutzer.** Die WPF-App wird self-contained veröffentlicht (.NET-Laufzeit enthalten). PowerShell läuft eingebettet über Microsoft.PowerShell.SDK; ein separat installiertes PowerShell 7 darf nicht vorausgesetzt werden. PowerShell 7 wird nur zum Entwickeln und Testen gebraucht.
- **Alles manuell einstellbar, keine Automatik nach Einsatzart.** Externe Dienste, KI-Anbieter, Freigabestufen und Scan-Bereiche (welche Ordner, Registry-Zweige, Nutzungsspuren) sind standardmäßig aus und werden einzeln vom Benutzer aktiviert, für alle gleich. Beim ersten Start wird „Privat“ oder „Firma“ abgefragt und gespeichert, aber nur als Information (z. B. für Lizenzhinweise oder spätere Funktionen). Es schaltet nichts automatisch frei oder ab.
- Schwerpunkt Sicherheit + KI. Keine eigene Paketverwaltung nachbauen: Updates und Deinstallation über winget (Fallback Registry/msiexec/Appx).
- **Mehrsprachig vorbereitet: neue Texte nie fest im Code.** App-Texte gehören in `.resx`-Ressourcen. Meldungen des Moduls kommen über `Import-LocalizedData` (`src/SoftwareInventory/SoftwareInventory.Strings.psd1`, abgerufen mit `Get-LocalizedString`; Sprachen später in Unterordnern wie `en-US\`). Gründe, Status und Fehler liefert das Modul als feste Codes (z. B. `ServiceDisabled`); erst die Anzeige übersetzt sie. Kommentarbasierte Hilfe und Doku sind davon ausgenommen. Bestehende Texte werden in einer eigenen kleinen Etappe nach 4a umgestellt; übersetzt wird vorerst nichts.
- **Gründe, Status und Meldungen des Moduls** kommen immer als `Code`, `Args` und `Text`, auch an den KI-Berater; Logik und Tests hängen nur am Code. `Text` stammt aus der psd1 in der UI-Sprache der App, damit Anzeige und Modultexte nie gemischt sind. Alte Protokolleinträge ohne Code werden unverändert angezeigt und als „älterer Eintrag“ gekennzeichnet.
- **Übersetzungen entstehen später per KI**, zuerst Englisch. Eine Prüfung durch Muttersprachler ist ausdrücklich erwünscht (README, Abschnitt „Übersetzungen beitragen“). Zum ersten Release gibt es die README auf Deutsch und Englisch.
- **Logs und Zwischenspeicher räumen sich selbst auf.** Alle Logs (Aktionsprotokoll, MSI-/Installer-Logs, Cache) liegen in einem eigenen App-Ordner und werden beim Start bereinigt: höchstens N Tage alt und höchstens X MB insgesamt, beides einstellbar (Standard: 30 Tage, 100 MB). Ältestes zuerst löschen. Installer-Logs nach erfolgreicher Aktion sofort löschen, nur bei Fehlern (komprimiert) länger aufheben. Keine Logs in Temp liegen lassen. Mit Tests absichern.

## Sicherheitsprinzipien

- Die KI darf Updates und Deinstallationen nur **vorschlagen**; ausgeführt wird erst nach Bestätigung im UI.
- App läuft als normaler Benutzer; Administratorrechte (UAC) nur für die einzelne Aktion anfordern.
- Jede Aktion wird protokolliert.
- Vor dem Senden an jedes Modell, auch an lokale, Benutzername, Rechnername und Benutzerpfade entfernen (`Protect-PrivateText`).
- API-Schlüssel (NVD, GitHub, KI-Server, später Plugin-Anbieter) nie ins Repository; über Windows-Anmeldeinformationsverwaltung oder Umgebungsvariablen.
- Ergebnisse aus Web-Recherche als „unbestätigt“ kennzeichnen.

## Git-Arbeitsweise

- `main` bleibt stabil: kein direktes Arbeiten auf `main`.
- Ein Branch pro Etappe, benannt nach dem Muster `etappe-<nr>-<thema>` (z. B. `etappe-1-inventar`).
- Nach jedem fertigen, lauffähigen Teilschritt committen (kleine Commits, Message auf Englisch).
- Ist die Etappe fertig, per Pull Request auf GitHub in `main` mergen.

## Fahrplan

Etappenweise vorgehen, siehe `docs/KONZEPT.md` Abschnitt „Fahrplan“. Etappe 3 (Oberfläche) ist fertig (3a Aktionen im Modul, 3b WPF-Grundgerüst, 3c Details und Aktions-Buttons, 3d Einstellungen). Aktuell: Etappe 4 (KI-Berater, nur lokal), aufgeteilt in 4a Tools, Bereinigung und Einstellungen im Modul, danach eine Zwischenetappe „Texte auslagern“ (bestehende Texte nach `.resx` bzw. `Import-LocalizedData`, Gründe und Status als Codes; noch keine Übersetzung), dann 4b Anbieter-Schnittstelle und Einstellungen in der App, 4c Chat-Seitenleiste mit Vorschlagskarten. Die Zwischenetappe kommt in zwei PRs: erst App-Texte, dann Modulmeldungen mit Codes. Vor dem ersten Release: englische Übersetzung per KI und README auf Englisch.
