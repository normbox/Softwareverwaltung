# Technische Daten

Stand: 24.10.2026 · Modulversion 0.1.0 (Etappe 1 abgeschlossen, Etappe 1b in Arbeit)

Dieses Dokument beschreibt, woraus das Programm besteht, was es auf dem Rechner tut, wo es Daten ablegt und mit welchen Diensten es spricht. Begründungen und Fahrplan stehen in [KONZEPT.md](KONZEPT.md), der Datensatzaufbau in [INVENTAR-SCHEMA.md](INVENTAR-SCHEMA.md).

Legende: **vorhanden** = im Code umgesetzt · **geplant** = laut Konzept vorgesehen, Angaben können sich noch ändern.

## Systemvoraussetzungen

| Punkt | Endbenutzer | Entwicklung |
| --- | --- | --- |
| Betriebssystem | Windows 10 oder 11, x64 (Arm64 geplant prüfen) | Windows 10 oder 11 |
| Laufzeit | keine Zusatzinstallation: .NET 10 und PowerShell-Engine sind in der App enthalten (self-contained) | .NET SDK 10, PowerShell 7.6 LTS |
| winget | Windows-Paket „App-Installer“ (enthält winget und dessen COM-Schnittstelle). Auf normalen Windows-10-(ab 1809) und -11-Installationen vorhanden und über den Store aktuell gehalten. Fehlt oft auf LTSC-, Server- und Sandbox-Systemen sowie frischen Images ohne Store-Update. Ohne App-Installer läuft die App weiter, nur ohne winget-Abgleich und winget-Aktionen; sie zeigt einen Hinweis und bietet die Installation über `Repair-WinGetPackageManager` an (nur nach Zustimmung). | ebenso, plus Modul `Microsoft.WinGet.Client` |
| Rechte | normaler Benutzer; Administratorrechte nur für einzelne Aktionen und den Tiefenscan (UAC) | normaler Benutzer |
| Netzwerk | optional; ohne Netzwerk funktioniert das reine Inventar | – |
| Windows PowerShell 5.1 | wird nicht verwendet und nicht unterstützt | – |

## Bestandteile

| Teil | Technik | Status |
| --- | --- | --- |
| Kern-Modul `SoftwareInventory` | PowerShell-Skriptmodul, `CompatiblePSEditions = Core`, PowerShell ≥ 7.6 | vorhanden |
| Inventarquellen | Registry (Uninstall-Schlüssel HKLM, HKLM\WOW6432Node, HKCU), `Get-AppxPackage`, `Get-WinGetPackage` | vorhanden |
| Portable Programme | Amcache, BAM, UserAssist, Prefetch, Prozesse, Autostart, Dateiscan, PE-Versionsinfo, Authenticode, SHA256 | Etappe 1b |
| Versionsabgleich | winget, GitHub Releases, Herstellerregeln, KI-Recherche (unbestätigt) | geplant (Etappe 2) |
| Sicherheitsprüfung | NVD CVE-API 2.0, CISA KEV, EPSS, OSV, GitHub Security Advisories | geplant (Etappe 2) |
| Desktop-App | .NET 10 WPF, Fluent-Design über WPF-UI, PowerShell eingebettet über `Microsoft.PowerShell.SDK` | geplant (Etappe 3) |
| KI-Berater | Provider-Abstraktion: Claude API (Tool-Use) oder Ollama/LM Studio (lokal) | geplant (Etappe 4) |
| MCP-Server | optionaler Zugang für Claude Desktop u. a. | geplant (Etappe 5) |

Abhängigkeiten und ihre Lizenzen: [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## Öffentliche Befehle des Moduls (Stand 0.1.0)

| Befehl | Wirkung |
| --- | --- |
| `Get-SoftwareInventory` | Liest alle Quellen und liefert einen Datensatz pro Programm |
| `Save-InventorySnapshot` | Speichert ein Inventar als JSON-Datei |
| `Get-InventorySnapshot` | Lädt gespeicherte Scans |
| `Compare-InventorySnapshot` | Zeigt Unterschiede zwischen zwei Scans |

Das Modul ändert in Etappe 1 nichts am System: Es liest nur.

## Was auf dem Rechner gelesen wird

| Bereich | Zugriff | Rechte | Status |
| --- | --- | --- | --- |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` (64 und 32 Bit) | lesen | Benutzer | vorhanden |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` | lesen, nur angemeldeter Benutzer | Benutzer | vorhanden |
| Installierte MSIX-/Store-Pakete samt Manifest | lesen | Benutzer | vorhanden |
| winget-Paketliste (über die WinGet-COM-Schnittstelle) | lesen | Benutzer | vorhanden |
| Amcache, BAM, Prefetch | lesen | Administrator | Etappe 1b |
| UserAssist, laufende Prozesse, Autostart | lesen | Benutzer | Etappe 1b |
| Gewählte Ordner (Downloads, Desktop, …) | Dateien auflisten, Versionsinfo und Signatur lesen, Hash bilden; **nichts ausführen** | Benutzer | Etappe 1b |

Hinweis: Amcache, BAM, UserAssist und Prefetch sind **Nutzungsspuren**. Sie zeigen, wer wann welches Programm gestartet hat. Das ist für die Erkennung portabler Programme nützlich, aber datenschutzrechtlich heikel, besonders auf Rechnern mit mehreren Personen und in Firmen. Siehe [PRIVACY.md](../PRIVACY.md) und [FIRMENEINSATZ.md](FIRMENEINSATZ.md).

## Was auf dem Rechner verändert wird (geplant)

Nur nach Bestätigung im UI, einzeln und protokolliert:

- `winget upgrade --id <Id> --exact` bzw. `winget uninstall --id <Id> --exact`
- Fallback: Deinstallationsbefehl aus der Registry, MSI über `msiexec /x {ProductCode}`
- Store-Apps: `Remove-AppxPackage`
- Optional vorher ein Windows-Wiederherstellungspunkt

Der KI-Berater kann Aktionen nur vorschlagen, nie selbst auslösen.

## Datenablage

| Daten | Ort | Inhalt | Status |
| --- | --- | --- | --- |
| Scans (Snapshots) | `%LOCALAPPDATA%\SoftwareInventory\scans\<yyyyMMdd-HHmmss-fff>.json` | Inventar mit Zeitstempel (UTC), Schema in [INVENTAR-SCHEMA.md](INVENTAR-SCHEMA.md) | vorhanden |
| Cache der Online-Abfragen | `%LOCALAPPDATA%\SoftwareInventory\cache\` (Vorschlag) | KEV-Liste, EPSS-Werte, CVE- und Versionsantworten | geplant |
| Aktionsprotokoll | `%LOCALAPPDATA%\SoftwareInventory\log\` (Vorschlag) | Zeitpunkt, Aktion, Programm, Befehl, Ergebnis | geplant |
| Einstellungen | `%APPDATA%\SoftwareInventory\settings.json` (Vorschlag) | eingerichtete Dienste und Bestätigungen der Bedingungen, gewählte Quellen, KI-Provider, Ordner für Dateiscan | geplant |
| Richtlinien (Firma) | `HKLM\SOFTWARE\Policies\Softwareverwaltung` (Vorschlag) | optional: vom Administrator festgelegte Einstellungen (Dienste, Freigabestufen, Schlüsselquellen); sperrt diese in der App | geplant |
| API-Schlüssel | Windows-Anmeldeinformationsverwaltung (Credential Manager) oder Umgebungsvariable; **nie** in Einstellungsdateien oder im Repository | Anthropic, NVD, GitHub, ggf. VirusTotal | geplant |

Alle Dateien liegen unverschlüsselt im Benutzerprofil und sind nur für den Benutzer (und Administratoren) lesbar. Scans können Benutzerpfade enthalten (z. B. `InstallLocation` unter `C:\Users\<Name>\...`) und damit den Benutzernamen. Es gibt noch keine automatische Löschung alter Scans; vorgesehen ist eine einstellbare Aufbewahrungsdauer.

Deinstallation des Programms: Die Ordner `%LOCALAPPDATA%\SoftwareInventory` und `%APPDATA%\SoftwareInventory` löschen und die Einträge des Programms in der Anmeldeinformationsverwaltung entfernen.

## Netzwerkverbindungen

Eine vollständige Liste mit Datenschutzbewertung steht in [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md). Kurzfassung für Firewall-Freigaben:

| Dienst | Host(s) | Wann | Status |
| --- | --- | --- | --- |
| winget-Quellen | `cdn.winget.microsoft.com`, `storeedgefd.dsx.mp.microsoft.com` | beim Lesen der winget-Daten und bei Aktionen | vorhanden (über winget) |
| GitHub API | `api.github.com` | Versionsabgleich | geplant |
| NVD | `services.nvd.nist.gov` | CVE-Abfragen | geplant |
| CISA KEV | `www.cisa.gov` | tägliches Laden der KEV-Liste | geplant |
| EPSS | `api.first.org` bzw. `epss.empiricalsecurity.com` (Download) | Priorisierung | geplant |
| OSV | `api.osv.dev` | Open-Source-Schwachstellen | geplant |
| Claude API | `api.anthropic.com` | nur wenn Cloud-KI gewählt | geplant |
| Ollama | `localhost:11434` (Standard) oder ein selbst betriebener Server | nur wenn lokale KI gewählt | geplant |
| VirusTotal | `www.virustotal.com` | nur nach ausdrücklicher Zustimmung | geplant, optional |

Die Hostnamen der geplanten Dienste sind vorläufig und vor der Umsetzung gegen die aktuelle Dokumentation der Anbieter zu prüfen. Proxy-Einstellungen des Systems werden übernommen (geplant).

## Sicherheitsmerkmale

- Läuft als normaler Benutzer, UAC nur für die einzelne Aktion.
- Liest Programmdateien nur (PE-Versionsinfo, Signatur, Hash), führt nichts aus.
- KI darf nur vorschlagen; jede Aktion braucht einen Klick und wird protokolliert.
- Vor dem Senden an Cloud-Modelle werden Benutzername, Rechnername und Benutzerpfade ersetzt.
- Ergebnisse aus Web-Recherche werden als „unbestätigt“ gekennzeichnet.
- Geplant für den Firmeneinsatz: signierte Skripte und signierte Releases (Authenticode), damit SmartScreen und AppLocker/WDAC-Regeln greifen.

## Telemetrie

Das Projekt selbst sendet keine Telemetrie und soll das auch künftig nicht tun. Zu beachten sind Bestandteile von Microsoft:

- **winget** sendet Nutzungsdaten gemäß den Windows-Diagnoseeinstellungen. Abschaltbar in den winget-Einstellungen (`winget settings`, Abschnitt `"telemetry": { "disable": true }`).
- **PowerShell** kennt Telemetrie (Umgebungsvariable `POWERSHELL_TELEMETRY_OPTOUT=1` schaltet sie ab). Ob die eingebettete Engine überhaupt sendet, ist in Etappe 3 zu prüfen; vorsorglich setzt die App die Variable vor dem Start der Runspace (geplant).

## Build und Veröffentlichung (geplant)

- `dotnet publish -c Release -r win-x64 --self-contained` erzeugt die App mit eingebetteter .NET-Laufzeit.
- Das Modul `Microsoft.WinGet.Client` (MIT) wird in fester Version mitgeliefert und aus dem App-Ordner geladen. Seine Version wird zusammen mit `Microsoft.PowerShell.SDK` aktualisiert, weil beide dieselbe .NET-/PowerShell-Version voraussetzen (Modul 1.29: .NET 10, PowerShell 7.6). winget selbst (App-Installer) wird nicht mitgeliefert.
- Jedes Release enthält `LICENSE`, `THIRD-PARTY-NOTICES.md` und die Hinweisdateien der eingebetteten Laufzeiten; der passende Quellcode ist über den Git-Tag des Releases verfügbar (GPLv3 § 6).
