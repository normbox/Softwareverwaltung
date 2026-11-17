# CLAUDE.md

Open-Source-Werkzeug für Windows: installierte Software inventarisieren, neue Versionen und Sicherheitslücken finden, per Klick aktualisieren oder deinstallieren, mit KI-Berater. Das vollständige Konzept steht in `docs/KONZEPT.md`; lies es vor größeren Änderungen.

## Zusammenarbeit

- Antworte auf Deutsch. Code, Bezeichner und Commit-Messages auf Englisch, Kommentare und Doku für Nutzer auf Deutsch.
- Bei Mehrdeutigkeit kurz nachfragen statt raten.
- Pflegeaufwand gering halten: neue Abhängigkeiten nur mit Begründung, Langzeitversionen bevorzugen.
- **Quelldateien ändern:** Quelltext nie über Shell-Quoting erzeugen oder ändern: kein Heredoc, `sed` oder `echo` in Bash oder PowerShell (die Shell verändert Backslashes und Escape-Folgen und hat schon Steuerzeichen in den Code geschrieben). Einzelne Änderungen mit Edit oder Write. Für viele Ersetzungen ein Hilfsskript mit Write als Datei im Scratchpad anlegen und dann ausführen; es liest und schreibt ausdrücklich UTF-8 (ohne Kodierungsfehler) und erhält BOM und Zeilenenden. **Das Schreibwerkzeug wandelt Unicode-Escape-Folgen (Backslash, u, vier Hexziffern) für unsichtbare Zeichen und Zeilentrenner in rohe Zeichen um.** Unsichtbare Zeichen und Steuerzeichen deshalb nie als Escape-Text schreiben: im Code `[char]0x1F` (PowerShell) bzw. `(char)0x1F` (C#), Regex-Zeichenklassen aus Codepunkten bauen, in XAML und resx `&#x1F;`; in Testdaten (JSON-Fälletabellen) den Platzhalter `{U+XXXX}` (z. B. `{U+2028}`), den Pester und xUnit beim Laden in das Zeichen umwandeln. Der Test `tests/Unit/SourceFiles.Tests.ps1` prüft alle Textdateien des Repositorys (Dateiliste aus `git ls-files`: u. a. `.ps1`, `.psm1`, `.psd1`, `.cs`, `.xaml`, `.resx`, `.md`, `.json`, `.csproj`, `.manifest`) auf rohe Steuerzeichen (außer Tab, CR und LF), Zeilentrenner (U+2028, U+2029), Bidi- und Zero-Width-Zeichen und ungültiges UTF-8.

## Architektur (verbindlich)

- **Kern = PowerShell-Modul.** Alle Logik (Inventar, Versionsabgleich, Sicherheitsprüfung, Aktionen) liegt im Modul und muss ohne Oberfläche lauffähig und testbar sein.
- **Oberfläche = .NET 10 WPF** mit Fluent-Design (WPF-UI). Die App ruft das Modul über die eingebettete PowerShell-Engine (`Microsoft.PowerShell.SDK`) auf und enthält selbst keine Fachlogik.
- **KI-Berater** nutzt die Modulfunktionen als Tools (`Get-AdvisorTool`, `Invoke-AdvisorTool`). Vorerst nur lokale Modelle über die OpenAI-kompatible Schnittstelle (Vorgaben: Ollama, LM Studio, Unsloth Studio, eigene Adresse; kein Standardmodell). Die App hat eine Anbieter-Schnittstelle; externe Anbieter (z. B. Claude API) kommen später als Plugin, ohne Umbau.
- Nur Windows 10/11; keine Linux-Kompatibilität einbauen.
- **Keine Zusatzinstallation für Endbenutzer.** Die WPF-App wird self-contained veröffentlicht (.NET-Laufzeit enthalten). PowerShell läuft eingebettet über Microsoft.PowerShell.SDK; ein separat installiertes PowerShell 7 darf nicht vorausgesetzt werden. PowerShell 7 wird nur zum Entwickeln und Testen gebraucht.
- **Alles manuell einstellbar, keine Automatik nach Einsatzart.** Externe Dienste, KI-Anbieter, Freigabestufen und Scan-Bereiche (welche Ordner, Registry-Zweige, Nutzungsspuren) sind standardmäßig aus und werden einzeln vom Benutzer aktiviert, für alle gleich. Beim ersten Start wird „Privat“ oder „Firma“ abgefragt und gespeichert, aber nur als Information (z. B. für Lizenzhinweise oder spätere Funktionen). Es schaltet nichts automatisch frei oder ab.
- Schwerpunkt Sicherheit + KI. Keine eigene Paketverwaltung nachbauen: Updates und Deinstallation über winget (Fallback Registry/msiexec/Appx).
- **Mehrsprachig vorbereitet: neue Texte nie fest im Code.** App-Texte gehören in `.resx`-Ressourcen. Meldungen des Moduls kommen über `Import-LocalizedData` (`src/SoftwareInventory/SoftwareInventory.Strings.psd1`, abgerufen mit `Get-LocalizedString`; Sprachen später in Unterordnern wie `en-US\`). Gründe, Status und Fehler liefert das Modul als feste Codes (z. B. `ServiceDisabled`); erst die Anzeige übersetzt sie. Kommentarbasierte Hilfe und Doku sind davon ausgenommen. Die bestehenden Texte sind umgestellt (Zwischenetappe „Texte auslagern“); übersetzt wird vorerst nichts.
- **Gründe, Status und Meldungen des Moduls** kommen immer als `Code`, `Args` und `Text`, auch an den KI-Berater; Logik und Tests hängen nur am Code. `Text` stammt aus der psd1 in der UI-Sprache der App, damit Anzeige und Modultexte nie gemischt sind. Alte Protokolleinträge ohne Code werden unverändert angezeigt und als „älterer Eintrag“ gekennzeichnet.
- **Übersetzungen entstehen später per KI**, zuerst Englisch. Eine Prüfung durch Muttersprachler ist ausdrücklich erwünscht (README, Abschnitt „Übersetzungen beitragen“). Zum ersten Release gibt es die README auf Deutsch und Englisch.
- **Logs und Zwischenspeicher räumen sich selbst auf.** Alle Logs (Aktionsprotokoll, MSI-/Installer-Logs, Cache) liegen in einem eigenen App-Ordner und werden beim Start bereinigt: höchstens N Tage alt und höchstens X MB insgesamt, beides einstellbar (Standard: 30 Tage, 100 MB). Ältestes zuerst löschen, über der Größengrenze zuerst den Zwischenspeicher, dann die Logs. Ausnahme: CIRCL-Bestände je Produkt haben eine eigene, einstellbare Grenze (Standard 200 MB) und werden außerdem gelöscht, wenn das Produkt nach einem Scan nicht mehr vorkommt. Installer-Logs nach erfolgreicher Aktion sofort löschen, nur bei Fehlern (komprimiert) länger aufheben. Keine Logs in Temp liegen lassen. Mit Tests absichern.

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

## Hooks (Claude Code, `.claude/settings.json`, Skripte in `.claude/hooks/`)

Die Hooks erzwingen Regeln dieser Datei. Sie sind Leitplanken, keine Garantie, und fail-open: Lässt sich die Eingabe nicht lesen, blockieren sie nie. `tests/Unit/Hooks.Tests.ps1` weist für jeden Hook nach, dass er bei Beispielen wirklich blockiert (Exit 2).

- `block-source-via-shell`: blockiert Schreiben auf Quelldateien über die Shell (Umleitung, `tee`, `sed -i`, `Set-Content`/`Out-File`, `WriteAllText`, `open(...).write`). Nur mit Quelldatei-Endung als Ziel; Temp und Scratchpad sind frei.
- `block-direct-tests`: blockiert `Invoke-Pester`, `dotnet test` und Skripte aus `tests/Sandbox`; erlaubt ist `tests/Invoke-IsolatedTests.ps1`.
- `block-git-risks`: blockiert `git commit/push/merge` auf `main` (und einen Push mit Ziel `main`), `push --force`/`-f`/`--force-with-lease`, `reset --hard`, `clean -f` und `gh pr merge` (Merge macht der Benutzer). `git checkout -- <Pfad>` gibt nur einen Hinweis.
- `check-control-chars`: prüft jede mit Edit/Write geänderte Quelldatei im Repository sofort auf rohe Steuerzeichen und ungültiges UTF-8 und meldet Zeile und Codepunkt.
- Die Zeichenbereiche und die Quelldatei-Endungen stehen einmal in `tests/Data/unsafe-chars.json` (Dezimal-Codepunkte); `SourceFiles.Tests.ps1` und der Hook `check-control-chars` lesen dieselbe Tabelle.
- Bewusst umgehen: den Hook für die Sitzung in `.claude/settings.local.json` überschreiben (die Datei ist nicht im Repository) und im PR begründen.

## Skills (`.claude/skills/`)

Wiederkehrende Abläufe als Slash-Befehle; sie halten sich an die Regeln dieser Datei, ersetzen sie aber nicht.

- `/etappe-test <Bereich>`: bauen, Teillauf von `tests/Invoke-IsolatedTests.ps1` mit Log und Frist, kurzes Ergebnis.
- `/pr-bereit`: Voll- bzw. Teillauf je nach Art des PR, `reviewer` einmal, PR-Text, Push und PR öffnen. Merge nie durch Claude.
- `/uebergabe`: `UEBERGABE.md` und Merk-Notiz am Sitzungsende aktualisieren (reine Doku, Sonnet genügt; Sicherheitslogik nur mit Opus).

## Fahrplan

Etappenweise vorgehen, siehe `docs/KONZEPT.md` Abschnitt „Fahrplan“. Etappe 3 (Oberfläche) ist fertig. Aktuell: Etappe 4 (KI-Berater, nur lokal). Fertig sind 4a (Tools, Bereinigung und Einstellungen im Modul) und die Zwischenetappe „Texte auslagern“ (App-Texte in `.resx`, Modulmeldungen mit Codes; noch keine Übersetzung), dazu Zwischenspeicher, Warteschlange, CPE-Zuordnung und CIRCL als zweite Quelle. Fertig ist auch 4b (Freigabestufen, Anbieter-Schnittstelle, Einstellungsseite). Aktuell 4c: Chat-Seitenleiste (4c-1), dann Vorschlagskarten (4c-2). Der lokale Lückenabzug (Offline-Modus) ist geplant, siehe `docs/KONZEPT.md`. Vor dem ersten Release: englische Übersetzung per KI und README auf Englisch.

<!-- BEGIN Claude-Team-Setup -->
## Arbeitsteilung mit Subagenten (Claude Code)

- Repo-Suchen: einzelne Nachschlagen (eine Datei, eine Funktion) mache ich selbst mit Grep/Glob. Den Subagenten `map` nur für größere Erkundungen über viele Dateien (Aufbau, Zusammenhänge); Aufrufstellen einer Funktion vor Umbenennen oder Signaturänderung an `callers`.
- **Tests starte ich selbst**, direkt mit `tests/Invoke-IsolatedTests.ps1` (kein `audit`-Subagent für normale Läufe). Nie `Invoke-Pester` oder `dotnet test` direkt: das Skript setzt ein eigenes APPDATA/LOCALAPPDATA, damit der echte App-Ordner unberührt bleibt.
- **Erst bauen, dann testen:** Vor jedem Testlauf baue ich die betroffenen Projekte selbst (`dotnet build`). Nur bei sauberem Build (keine Fehler) starte ich die Tests; sonst erst den Build reparieren.
- **Testumfang:** Während der Arbeit laufen nur die betroffenen Tests, gezielt über `-PesterPath` (Dateien/Ordner unter `tests/Unit/`) bzw. `-XunitFilter`. Der volle Lauf kommt nur vor dem Abschluss (Commit) eines Teilschritts und vor dem PR (dort mit `-IncludeIntegration`).
- **Auf das Ende warten (immer mit Frist):** Das Skript mit Ausgabe in eine Logdatei starten (PowerShell: `pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 … *> <Logdatei>`; Git Bash: `… > <Logdatei> 2>&1`, dort ist `*>` ein Glob) und **nur** auf die Abschlusszeile `ISOLATED-TESTS-EXIT <Code>` im Log warten (0 bestanden, 1 Fehlschlag, 2 Abbruch durch die Parameterprüfung, 3 unerwarteter Fehler, 4 nichts oder nicht alles ausgeführt) oder auf die PID genau dieses Laufs. Frist: voller Lauf höchstens 30 Minuten, Teillauf höchstens 10 Minuten. Nie darauf warten, dass kein `dotnet`-Prozess mehr läuft (VS Code hält eigene offen), nie ohne Timeout. Fehlt die Abschlusszeile nach der Frist: „Lauf nicht beendet“ melden. Skripte aus `tests/Sandbox` nie starten.
- **Reine Doku-/Regel-PRs ohne Code** (nur `.md`, Agentendefinitionen o. Ä.) brauchen weder `reviewer` noch den vollen Lauf, nur den Teillauf `-PesterPath tests/Unit/SourceFiles.Tests.ps1`.
- `audit` (`.claude/agents/audit.md`) bleibt als Datei, aber nur für Ausnahmefälle (z. B. Prüfung in einer sauberen Kopie des committeten Stands auf ausdrücklichen Wunsch). Er sieht nur committete Stände.
- Vor jedem PR läuft der Subagent `reviewer` genau einmal (Sicherheit, Fehler, Projektregeln; nur lesend, sieht nur committete Stände). Nur wenn kritische Funde behoben wurden, läuft er danach erneut, nicht nach mittleren oder geringen. Den Bericht fasse ich kurz zusammen; nicht behobene mittlere und geringe Funde stehen mit Begründung in der PR-Beschreibung.
- In der Hauptsitzung nur Dateien lesen, die gleich bearbeitet werden.
- **Modellwahl:** Für Doku, Umbenennungen und UEBERGABE-Updates genügt Sonnet. Sicherheitslogik (Helfer, Registry, Rechte, Prüfregeln) nur mit Opus. Startet eine Sitzung mit Sonnet eine Aufgabe, die Sicherheitslogik berührt, weist Claude den Benutzer darauf hin und schlägt `/model opus` vor. `reviewer` läuft immer mit Opus.
<!-- END Claude-Team-Setup -->
