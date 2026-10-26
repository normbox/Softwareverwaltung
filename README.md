# Softwareverwaltung

Open-Source-Werkzeug für Windows, das installierte Software erfasst, veraltete und unsichere Versionen erkennen soll und Updates oder Deinstallationen vorschlägt.

[![Lizenz: GPLv3](https://img.shields.io/badge/Lizenz-GPLv3-blue.svg)](LICENSE)
![Oberfläche: .NET 10 WPF](https://img.shields.io/badge/Oberfl%C3%A4che-.NET%2010%20WPF-512BD4.svg)
![PowerShell 7.6](https://img.shields.io/badge/PowerShell-7.6-5391FE.svg)
![Plattform: Windows 10/11](https://img.shields.io/badge/Plattform-Windows%2010%2F11-0078D4.svg)
![Status: in Entwicklung](https://img.shields.io/badge/Status-in%20Entwicklung-orange.svg)

## Was es kann

| Funktion | Stand |
| --- | --- |
| Inventar aus Registry (Rechner und Benutzer), winget und Store-Apps, zusammengeführt zu einem Datensatz pro Programm | vorhanden |
| Portable und nicht registrierte Programme (Nutzungsspuren, Dateiscan von Ordnern oder Laufwerken, Signaturprüfung, optional SHA256) | vorhanden |
| Einstellungen: jede Quelle und jeder Scan-Bereich einzeln schaltbar, standardmäßig aus | vorhanden |
| Verfügbare Updates laut winget (`AvailableVersion`) | vorhanden |
| Scans als JSON speichern und vergleichen (neu, entfernt, Version geändert) | vorhanden |
| Versionsabgleich über GitHub Releases (Produktkatalog) und winget-Suche für Programme ohne winget-ID (`Test-SoftwareUpdate`) | vorhanden (Etappe 2a) |
| Versionsabgleich über Herstellerregeln | geplant |
| Schwachstellen über NVD, CISA KEV und EPSS für Programme mit Katalogeintrag (`Get-SoftwareVulnerability`) | vorhanden (Etappe 2b) |
| Ampel (Rot, Gelb, Grün, Grau mit Grund) und HTML-Sicherheitsbericht (`Get-SecurityRating`, `Export-SecurityReport`) | vorhanden (Etappe 2c) |
| Weitere Schwachstellenquellen (OSV, GitHub Security Advisories) | geplant |
| Aktualisieren über winget und Deinstallieren (winget, MSI, Store-App, Registry) mit Bestätigung, UAC nur pro Aktion, Prüfung danach, Protokoll und optionalem Wiederherstellungspunkt (`Update-Software`, `Uninstall-Software`, `Get-ActionLog`) | vorhanden (Etappe 3a) |
| Oberfläche (WPF, Fluent-Design): Hauptliste mit Ampel, Suche und Filtern, Hinweis bei fehlendem winget; läuft ohne Zusatzinstallation | vorhanden (Etappe 3b) |
| Begleitpakete (z. B. Kontextmenü-Erweiterungen als Sparse Package) werden ihrem Programm zugeordnet | vorhanden (Etappe 3b) |
| Details und Buttons für Aktualisieren und Deinstallieren in der Oberfläche | geplant (Etappe 3c) |
| KI-Berater mit lokalen Modellen (Ollama, LM Studio, Unsloth Studio), externe Anbieter später als Plugin | in Arbeit |

Updates und Deinstallationen laufen über winget (Fallback Registry/msiexec/Appx). Eine eigene Paketverwaltung wird nicht nachgebaut.

## Grundsätze

- **Alles standardmäßig aus und manuell einstellbar.** Quellen, Scan-Bereiche, externe Dienste und KI-Anbieter werden einzeln vom Benutzer aktiviert, für alle gleich. Es gibt keine Automatik nach Einsatzart. Ohne Einstellungen liest das Modul nichts.
- **Keine Zusatzinstallation für Endbenutzer.** Die App wird self-contained veröffentlicht, bettet PowerShell über `Microsoft.PowerShell.SDK` ein und bringt das winget-Modul mit. PowerShell 7 wird nur zum Entwickeln und Testen gebraucht.
- **Die KI schlägt nur vor.** Updates und Deinstallationen werden erst nach Bestätigung in der Oberfläche ausgeführt; jede Aktion wird protokolliert.
- **Freigabestufen für Daten an die KI** (geplant): Der Benutzer legt fest, was an ein Modell übertragen wird. Vor dem Senden an ein Modell, auch an ein lokales, werden Benutzername, Rechnername und Benutzerpfade entfernt.
- **Normale Benutzerrechte.** Administratorrechte (UAC) nur für die einzelne Aktion.

## Stand und Fahrplan

Einzelheiten in [docs/KONZEPT.md](docs/KONZEPT.md), Abschnitt „Fahrplan“.

- [x] 1. Inventar-Modul: Registry, winget, Store-Apps, JSON-Snapshots, ohne Oberfläche testbar
- [x] 1b. Portable Programme und Einstellungen (alles standardmäßig aus)
- [x] 2. Versions- und Sicherheitsprüfung: winget- und GitHub-Provider, NVD- und KEV-Abgleich, Ampel, zunächst HTML-Bericht
  - [x] 2a. Versionsvergleich, Produktkatalog, neueste Version über winget, GitHub und winget-Suche
  - [x] 2b. Schwachstellen: CPE-Zuordnung über den Katalog, NVD, CISA KEV, EPSS
  - [x] 2c. Ampel und HTML-Bericht
- [x] 3. Oberfläche: WPF-App mit Liste, Details, Update- und Deinstallations-Buttons
  - [x] 3a. Aktionen im Modul: Aktualisieren, Deinstallieren, Protokoll, Wiederherstellungspunkt
  - [x] 3b. WPF-Grundgerüst mit eingebettetem Modul und Hauptliste
  - [x] 3c. Details und Aktions-Buttons mit Bestätigung
  - [x] 3d. Einstellungen in der Oberfläche
- [ ] 4. KI-Berater: Tools, lokale Modelle (OpenAI-kompatibel), Chat-Seitenleiste
  - [x] 4a. Tools, Bereinigung und Einstellungen im Modul
  - [ ] Zwischenetappe: bestehende Texte auslagern (.resx, Import-LocalizedData, Codes), noch ohne Übersetzung
  - [ ] 4b. Anbieter-Schnittstelle und Einstellungen in der App
  - [ ] 4c. Chat-Seitenleiste mit Vorschlagskarten
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

# Standardmäßig ist alles aus. Bereiche einzeln aktivieren oder eine Vorlage wählen:
Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx
Set-InventorySetting -Preset Quick                           # alle Quellen und Spuren, Dateiscan im Benutzerprofil
Get-InventorySetting                                         # aktuelle Auswahl anzeigen

Get-SoftwareInventory | Format-Table Name, Version, AvailableVersion, Sources
Get-SoftwareInventory | Where-Object AvailableVersion        # Programme mit Update laut winget
Get-SoftwareInventory | Save-InventorySnapshot               # Scan unter %LOCALAPPDATA%\SoftwareInventory\scans speichern
Compare-InventorySnapshot                                    # Unterschied der letzten beiden Scans

# Portable und nicht registrierte Programme
Get-PortableSoftware | Format-Table Name, Version, Flags, FilePath   # mit den aktivierten Bereichen
Get-ScanDrive                                                        # wählbare Laufwerke
Get-PortableSoftware -Drive C, D -ComputeHash                        # einmalig ganze Laufwerke, mit SHA256

# Neueste Versionen prüfen (externe Dienste vorher einzeln aktivieren)
Set-InventorySetting -Enable GitHub, WingetSearch
@(Get-SoftwareInventory) + @(Get-PortableSoftware) | Test-SoftwareUpdate | Where-Object Status -eq Outdated
Compare-SoftwareVersion 24.08 24.9                                    # -1: älter

# Bekannte Sicherheitslücken (externe Dienste vorher einzeln aktivieren; ohne NVD-Schlüssel gedrosselt)
Set-ServiceCredential -Service NVD -Secret (Read-Host "NVD-API-Schlüssel" -AsSecureString)   # optional, Windows-Anmeldeinformationsverwaltung
Set-InventorySetting -Enable NVD, KEV, EPSS
(Get-SoftwareInventory | Get-SoftwareVulnerability).Vulnerabilities | Where-Object Kev   # aktiv ausgenutzte Lücken

# Ampel und HTML-Bericht
@(Get-SoftwareInventory) + @(Get-PortableSoftware) | Get-SecurityRating | Export-SecurityReport -Path .\Sicherheitsbericht.html

# Aktualisieren und Deinstallieren (erst ansehen, dann ausführen; UAC nur bei Bedarf)
Get-SoftwareInventory | Where-Object AvailableVersion | Update-Software -WhatIf
Get-SoftwareInventory | Where-Object Name -eq 'Contoso Tool' | Uninstall-Software
Get-ActionLog -Last 10 | Format-Table StartedAt, Action, Name, Method, Elevated, Result
Set-InventorySetting -Enable RestorePoint                              # optional: vorher Wiederherstellungspunkt

# Installiertes und Portables in einem Snapshot
@(Get-SoftwareInventory) + @(Get-PortableSoftware) | Save-InventorySnapshot
```

Fehlt `Microsoft.WinGet.Client`, warnt das Modul und liefert Registry und Store-Apps ohne winget-Daten. `Test-WingetAvailability` zeigt, ob winget und das Modul nutzbar sind.

### Oberfläche

Zusätzlich nötig: .NET SDK 10 (`winget install Microsoft.DotNet.SDK.10`). Beim ersten Build wird `Microsoft.WinGet.Client` in fester Version aus der PowerShell Gallery geladen und per SHA256 geprüft.

```powershell
dotnet build                                               # App und Tests bauen
dotnet test                                                # Tests der App (eingebettete Engine, ViewModel)
dotnet run --project src/Softwareverwaltung.App            # App starten
.\build\Publish-App.ps1                                    # self-contained nach artifacts\ (Ordner und ZIP)
.\tests\Sandbox\Start-AppSandbox.ps1                       # veröffentlichte App ohne .NET, PowerShell 7 und winget prüfen
```

Die App liest dieselben Einstellungen wie das Modul. Auf der Seite „Einstellungen“ lassen sich alle Schalter, der Dateiscan, die externen Dienste, die API-Schlüssel und die Aufbewahrung der Logs einstellen; gespeichert wird mit „Speichern“. Beim ersten Start fragt die App „Privat“ oder „Firma“ ab und zeigt die passenden Hinweise zu den Nutzungsbedingungen der Dienste; eingeschaltet wird dabei nichts.

Tests:

```powershell
Invoke-Pester ./tests/Unit                                 # Unit-Tests
Invoke-Pester ./tests/Integration                          # gegen das echte System (liest nur)
.\tests\Sandbox\Start-ActionSandbox.ps1                    # Aktionen echt testen, nur in Windows Sandbox
Invoke-ScriptAnalyzer ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

Fremdkomponenten und ihre Lizenzen: [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

Weitere Unterlagen: [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md) (Einrichtung, Machbarkeitsprüfung), [docs/INVENTAR-SCHEMA.md](docs/INVENTAR-SCHEMA.md) (Aufbau der Datensätze und Snapshots, Ausschlussregeln, Einstellungen), [docs/VERSIONSABGLEICH.md](docs/VERSIONSABGLEICH.md) (Quellen und Versionsvergleich), [docs/SCHWACHSTELLEN.md](docs/SCHWACHSTELLEN.md) (NVD, KEV, EPSS), [docs/BERICHT.md](docs/BERICHT.md) (Ampel und Bericht), [docs/AKTIONEN.md](docs/AKTIONEN.md) (Aktualisieren, Deinstallieren, Adminrechte, Protokoll), [docs/BERATER.md](docs/BERATER.md) (KI-Berater, Tools, Bereinigung), [docs/KATALOG.md](docs/KATALOG.md) (Produktkatalog, Beiträge).

## Datenschutz

Das Modul läuft lokal und sendet keine Daten. Scans, Aktionsprotokoll und Einstellungen werden nur auf dem eigenen Rechner gespeichert (`%LOCALAPPDATA%\SoftwareInventory`, `%APPDATA%\SoftwareInventory\settings.json`). Logs und Zwischenspeicher räumen sich selbst auf (Standard: 30 Tage, 100 MB). Spätere Funktionen, die externe Dienste nutzen (Schwachstellen-Datenbanken, KI-Anbieter), senden erst nach ausdrücklicher Freigabe durch den Benutzer. Eine ausführliche Datenschutzerklärung folgt als `PRIVACY.md`.

## Mitmachen

Fehlermeldungen und Vorschläge bitte als [Issue](https://github.com/normbox/Softwareverwaltung/issues), Änderungen als Pull Request gegen `main`. Code, Bezeichner und Commit-Messages sind auf Englisch, Kommentare und Dokumentation für Nutzer auf Deutsch. Neue Abhängigkeiten bitte begründen; Langzeitversionen werden bevorzugt.

## Lizenz und Haftung

Lizenziert unter der [GNU General Public License v3.0](LICENSE).

Die Software wird ohne jede Gewähr bereitgestellt, soweit gesetzlich zulässig (siehe Abschnitte 15 und 16 der GPLv3). Die Nutzung, insbesondere das Aktualisieren und Deinstallieren von Programmen, erfolgt auf eigene Verantwortung.
