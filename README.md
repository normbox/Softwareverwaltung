# Softwareverwaltung

Open-Source-Werkzeug für Windows, das installierte Software erfasst, veraltete und unsichere Versionen erkennen soll und Updates oder Deinstallationen vorschlägt.

[![Lizenz: GPLv3](https://img.shields.io/badge/Lizenz-GPLv3-blue.svg)](LICENSE)
![Oberfläche: .NET 10 (geplant)](https://img.shields.io/badge/Oberfl%C3%A4che-.NET%2010%20(geplant)-512BD4.svg)
![PowerShell 7.6](https://img.shields.io/badge/PowerShell-7.6-5391FE.svg)
![Plattform: Windows 10/11](https://img.shields.io/badge/Plattform-Windows%2010%2F11-0078D4.svg)
![Status: in Entwicklung](https://img.shields.io/badge/Status-in%20Entwicklung-orange.svg)

## Was es kann

| Funktion | Stand |
| --- | --- |
| Inventar aus Registry (Rechner und Benutzer), winget und Store-Apps, zusammengeführt zu einem Datensatz pro Programm | vorhanden |
| Verfügbare Updates laut winget (`AvailableVersion`) | vorhanden |
| Scans als JSON speichern und vergleichen (neu, entfernt, Version geändert) | vorhanden |
| Portable und nicht registrierte Programme (Nutzungsspuren, Dateiscan, Signaturprüfung) | in Prüfung ([PR #2](https://github.com/normbox/Softwareverwaltung/pull/2)) |
| Versionsabgleich über weitere Quellen (GitHub Releases, Herstellerregeln) | geplant |
| Sicherheitsprüfung (NVD, CISA KEV, EPSS, OSV) mit Ampel | geplant |
| Oberfläche (WPF) mit Buttons für Aktualisieren und Deinstallieren über winget | geplant |
| KI-Berater, wahlweise lokal (Ollama) oder Cloud (Claude API) | geplant |

Updates und Deinstallationen laufen über winget (Fallback Registry/msiexec/Appx). Eine eigene Paketverwaltung wird nicht nachgebaut.

## Grundsätze

- **Alles standardmäßig aus und manuell einstellbar.** Quellen, Scan-Bereiche, externe Dienste und KI-Anbieter werden einzeln vom Benutzer aktiviert, für alle gleich. Es gibt keine Automatik nach Einsatzart. Im Modul umgesetzt mit Etappe 1b (PR #2); bis dahin liest `Get-SoftwareInventory` ohne Angabe alle drei Quellen.
- **Keine Zusatzinstallation für Endbenutzer.** Die spätere App wird self-contained veröffentlicht und bettet PowerShell über `Microsoft.PowerShell.SDK` ein. PowerShell 7 wird nur zum Entwickeln und Testen gebraucht.
- **Die KI schlägt nur vor.** Updates und Deinstallationen werden erst nach Bestätigung in der Oberfläche ausgeführt; jede Aktion wird protokolliert.
- **Freigabestufen für Daten an die KI** (geplant): Der Benutzer legt fest, was an ein Modell übertragen wird. Vor dem Senden an Cloud-Modelle werden Benutzername, Rechnername und Benutzerpfade entfernt.
- **Normale Benutzerrechte.** Administratorrechte (UAC) nur für die einzelne Aktion.

## Stand und Fahrplan

Einzelheiten in [docs/KONZEPT.md](docs/KONZEPT.md), Abschnitt „Fahrplan“.

- [x] 1. Inventar-Modul: Registry, winget, Store-Apps, JSON-Snapshots, ohne Oberfläche testbar
- [ ] 1b. Portable Programme und Einstellungen (alles standardmäßig aus) – in Prüfung, [PR #2](https://github.com/normbox/Softwareverwaltung/pull/2)
- [ ] 2. Versions- und Sicherheitsprüfung: winget- und GitHub-Provider, NVD- und KEV-Abgleich, Ampel, zunächst HTML-Bericht
- [ ] 3. Oberfläche: WPF-App mit Liste, Details, Update- und Deinstallations-Buttons
- [ ] 4. KI-Berater: Tools, Claude API und Ollama, Chat-Seitenleiste
- [ ] 5. Ausbau: Herstellerkatalog, MCP-Server, geplante Scans mit Benachrichtigung
- [ ] 6. Firmentauglich: zentrale Sammlung mehrerer PCs, Richtlinien, signierte Skripte

## Schnellstart für Entwickler

Voraussetzungen: Windows 10/11, PowerShell 7.6, Git. Für die winget-Daten zusätzlich das Modul `Microsoft.WinGet.Client`, für die Tests Pester und PSScriptAnalyzer. Administratorrechte sind nicht nötig.

```powershell
winget install --id Microsoft.PowerShell --exact
pwsh -c "Install-PSResource Pester,PSScriptAnalyzer,Microsoft.WinGet.Client -Scope CurrentUser -TrustRepository"

git clone https://github.com/normbox/Softwareverwaltung.git
cd Softwareverwaltung
```

In `pwsh`:

```powershell
Import-Module ./src/SoftwareInventory

Get-SoftwareInventory | Format-Table Name, Version, AvailableVersion, Sources
Get-SoftwareInventory -Source Registry, Appx               # nur bestimmte Quellen
Get-SoftwareInventory | Where-Object AvailableVersion      # Programme mit Update laut winget
Get-SoftwareInventory | Save-InventorySnapshot             # Scan unter %LOCALAPPDATA%\SoftwareInventory\scans speichern
Compare-InventorySnapshot                                  # Unterschied der letzten beiden Scans
```

Fehlt `Microsoft.WinGet.Client`, warnt das Modul und liefert Registry und Store-Apps ohne winget-Daten.

Tests:

```powershell
Invoke-Pester ./tests/Unit                                 # Unit-Tests
Invoke-Pester ./tests/Integration                          # gegen das echte System
Invoke-ScriptAnalyzer ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Weitere Unterlagen: [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md) (Einrichtung, Machbarkeitsprüfung), [docs/INVENTAR-SCHEMA.md](docs/INVENTAR-SCHEMA.md) (Aufbau der Datensätze und Snapshots).

## Datenschutz

Das Modul läuft lokal und sendet keine Daten. Scans werden nur auf dem eigenen Rechner gespeichert (`%LOCALAPPDATA%\SoftwareInventory`). Spätere Funktionen, die externe Dienste nutzen (Schwachstellen-Datenbanken, KI-Anbieter), senden erst nach ausdrücklicher Freigabe durch den Benutzer. Eine ausführliche Datenschutzerklärung folgt als `PRIVACY.md`.

## Mitmachen

Fehlermeldungen und Vorschläge bitte als [Issue](https://github.com/normbox/Softwareverwaltung/issues), Änderungen als Pull Request gegen `main`. Code, Bezeichner und Commit-Messages sind auf Englisch, Kommentare und Dokumentation für Nutzer auf Deutsch. Neue Abhängigkeiten bitte begründen; Langzeitversionen werden bevorzugt.

## Lizenz und Haftung

Lizenziert unter der [GNU General Public License v3.0](LICENSE).

Die Software wird ohne jede Gewähr bereitgestellt, soweit gesetzlich zulässig (siehe Abschnitte 15 und 16 der GPLv3). Die Nutzung, insbesondere das Aktualisieren und Deinstallieren von Programmen, erfolgt auf eigene Verantwortung.
