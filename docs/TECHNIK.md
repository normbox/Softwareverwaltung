# Technische Daten

Stand: 28.10.2026 · Etappen 1 bis 3 und 4a fertig; Detailansicht, Zwischenspeicher und Update-Warteschlange umgesetzt; Etappe 4b (KI-Berater in der App) als Nächstes

Dieses Dokument beschreibt, woraus das Programm besteht, was es auf dem Rechner tut, wo es Daten ablegt und mit welchen Diensten es spricht. Begründungen und Fahrplan stehen in [KONZEPT.md](KONZEPT.md), der Datensatzaufbau in [INVENTAR-SCHEMA.md](INVENTAR-SCHEMA.md), Aktionen in [AKTIONEN.md](AKTIONEN.md).

Legende: **vorhanden** = im Code umgesetzt · **geplant** = laut Konzept vorgesehen, Angaben können sich noch ändern.

## Systemvoraussetzungen

| Punkt | Endbenutzer | Entwicklung |
| --- | --- | --- |
| Betriebssystem | Windows 10 oder 11, x64 | Windows 10 oder 11 |
| Laufzeit | keine Zusatzinstallation: .NET 10 und die PowerShell-Engine sind in der App enthalten (self-contained) | .NET SDK 10, PowerShell 7.6 LTS |
| Windows PowerShell 5.1 | wird nur für den erhöhten Helfer gestartet (Aktionen mit Administratorrechten); auf jedem Windows 10/11 vorhanden | ebenso |
| winget | Windows-Paket „App-Installer“ (enthält winget und dessen COM-Schnittstelle). Auf normalen Windows-10-(ab 1809) und -11-Installationen vorhanden und über den Store aktuell gehalten. Fehlt oft auf LTSC-, Server- und Sandbox-Systemen. Ohne App-Installer läuft die App weiter, nur ohne winget-Abgleich und winget-Aktionen; sie zeigt einen Hinweis und bietet die Installation über `Repair-WinGetPackageManager` an (nur nach Bestätigung). | ebenso, plus Modul `Microsoft.WinGet.Client` |
| Rechte | normaler Benutzer; Administratorrechte (UAC) nur für die einzelne Aktion bzw. einmal für den erhöhten Teil einer Update-Warteschlange und für den Wiederherstellungspunkt | normaler Benutzer |
| Netzwerk | optional; ohne Netzwerk funktioniert das Inventar, Online-Ergebnisse kommen dann aus dem Zwischenspeicher (als veraltet gekennzeichnet) | – |

## Bestandteile

| Teil | Technik | Status |
| --- | --- | --- |
| Kern-Modul `SoftwareInventory` | PowerShell-Skriptmodul, `CompatiblePSEditions = Core`, PowerShell ≥ 7.6 | vorhanden |
| Inventarquellen | Registry (Uninstall-Schlüssel HKLM, HKLM\WOW6432Node, HKCU), `Get-AppxPackage`, `Get-WinGetPackage` | vorhanden |
| Portable Programme | Nutzungsspuren (UserAssist, laufende Prozesse, Autostart, geplante Aufgaben), Dateisuche in Laufwerken oder Ordnern, PE-Versionsinfo, Authenticode, optional SHA256 | vorhanden |
| Versionsabgleich | winget, GitHub Releases (Katalog), winget-Suche (unbestätigt) | vorhanden |
| Sicherheitsprüfung | NVD CVE-API 2.0, CISA KEV, EPSS; Ampel und HTML-Bericht | vorhanden |
| Aktionen | Aktualisieren und Deinstallieren über winget, MSI, Deinstallationsbefehl, Store-App; Update-Warteschlange | vorhanden |
| Desktop-App | .NET 10 WPF, Fluent-Design über WPF-UI, PowerShell eingebettet über `Microsoft.PowerShell.SDK` | vorhanden |
| KI-Berater | Werkzeuge und Bereinigung im Modul (4a) vorhanden; Anbindung in der App über die OpenAI-kompatible Schnittstelle lokaler Server (4b), Chat (4c); Cloud-Anbieter später als Erweiterung | teilweise, geplant |
| MCP-Server | optionaler Zugang für andere KI-Programme | geplant (Etappe 5) |

Abhängigkeiten und ihre Lizenzen: [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## Öffentliche Befehle des Moduls

| Bereich | Befehle |
| --- | --- |
| Inventar | `Get-SoftwareInventory`, `Get-PortableSoftware`, `Invoke-InventoryScan`, `Find-InstalledSoftware`, `Get-ScanDrive`, `Resolve-InstallLocation` |
| Scans | `Save-InventorySnapshot`, `Get-InventorySnapshot`, `Compare-InventorySnapshot` |
| Versionen und Sicherheit | `Test-SoftwareUpdate`, `Compare-SoftwareVersion`, `Get-SoftwareVulnerability`, `Get-SecurityRating`, `Export-SecurityReport`, `Find-CpeCandidate`, `Get-CpeMapping`, `Set-CpeMapping`, `Remove-CpeMapping`, `Clear-CheckCache`, `Get-RefreshEstimate` |
| Aktionen | `Update-Software`, `Uninstall-Software`, `Get-UpdateQueuePlan`, `Invoke-UpdateQueue`, `Get-ActionLog`, `Test-WingetAvailability`, `Install-WingetPackageManager` |
| Einstellungen und Schlüssel | `Get-InventorySetting`, `Set-InventorySetting`, `Get-SettingPreset`, `Get-ServiceTermsNotice`, `Set-ServiceCredential`, `Remove-ServiceCredential`, `Get-ServiceCredentialStatus` |
| KI-Berater | `Get-AdvisorTool`, `Invoke-AdvisorTool`, `Set-AdvisorContext`, `Get-AdvisorEndpointPreset` |

Jeder Befehl hat eine kommentarbasierte Hilfe (`Get-Help <Befehl> -Full`).

## Was auf dem Rechner gelesen wird

| Bereich | Zugriff | Rechte | Status |
| --- | --- | --- | --- |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` (64 und 32 Bit) | lesen | Benutzer | vorhanden |
| `HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall` | lesen, nur angemeldeter Benutzer | Benutzer | vorhanden |
| Installierte MSIX-/Store-Pakete samt Manifest | lesen | Benutzer | vorhanden |
| winget-Paketliste (über die WinGet-COM-Schnittstelle) | lesen | Benutzer | vorhanden |
| Windows Installer: Komponentenpfade eines MSI-Produkts (nur beim Aufklappen der Details) | lesen | Benutzer | vorhanden |
| Nutzungsspuren: UserAssist, laufende Prozesse, Autostart, geplante Aufgaben | lesen, nur wenn eingeschaltet | Benutzer | vorhanden |
| Gewählte Laufwerke oder Ordner | Dateien auflisten, Versionsinfo und Signatur lesen, optional Hash bilden; **nichts ausführen** | Benutzer | vorhanden |

Amcache, BAM und Prefetch werden nicht gelesen.

Hinweis: Nutzungsspuren zeigen, wer wann welches Programm gestartet hat. Das ist für die Erkennung portabler Programme nützlich, aber datenschutzrechtlich heikel, besonders auf Rechnern mit mehreren Personen und in Firmen. Siehe [PRIVACY.md](../PRIVACY.md) und [FIRMENEINSATZ.md](FIRMENEINSATZ.md).

## Was auf dem Rechner verändert wird

Nur nach Bestätigung im UI (mit dem genauen Befehl), protokolliert, Administratorrechte nur wenn nötig. Einzelheiten in [AKTIONEN.md](AKTIONEN.md).

- `winget upgrade --id <Id> --exact --source <Quelle des Pakets> --silent --accept-source-agreements --disable-interactivity …` bzw. `winget uninstall …` mit denselben Angaben; bei der Quelle `msstore` steht `--accept-source-agreements` nur nach gespeicherter Zustimmung des Benutzers
- Deinstallieren ohne winget je nach Programm: MSI über `msiexec /x {ProductCode}`, Deinstallationsbefehl aus der Registry (keine Skript-Interpreter), Store-Apps über `Remove-AppxPackage`. Nach einem Fehlschlag wird die nächste Methode nur vorgeschlagen, nie automatisch genutzt.
- Optional vorher ein Windows-Wiederherstellungspunkt (bei der Warteschlange einer für alle)
- `Repair-WinGetPackageManager`, wenn winget fehlt und der Benutzer zustimmt

Der KI-Berater kann Aktionen nur vorschlagen, nie selbst auslösen.

## Datenablage

| Daten | Ort | Inhalt | Status |
| --- | --- | --- | --- |
| Einstellungen | `%APPDATA%\SoftwareInventory\settings.json` | eingeschaltete Quellen, Dienste und Nutzungsspuren, Dateisuche, Haltbarkeit des Zwischenspeichers, Aufbewahrung der Logs, KI-Server | vorhanden |
| Eigene CPE-Zuordnungen | `%APPDATA%\SoftwareInventory\cpe-map.json` | vom Benutzer bestätigte Zuordnungen Programm → CPE | vorhanden |
| Zwischenspeicher der Online-Abfragen | `%LOCALAPPDATA%\SoftwareInventory\cache\<Dienst>\`, Index je Programm in `cache\index\` | Antworten von NVD, KEV, EPSS, GitHub und winget-Suche mit Abrufzeit | vorhanden |
| Aktionsprotokoll | `%LOCALAPPDATA%\SoftwareInventory\logs\actions\<Datum>.jsonl` | Zeitpunkt, Benutzer, Aktion, Programm, Befehl, Ergebnis | vorhanden |
| Installer-Logs | `%LOCALAPPDATA%\SoftwareInventory\logs\installer\` | nur nach Fehlern, komprimiert | vorhanden |
| Fehlerprotokoll der App | `%LOCALAPPDATA%\SoftwareInventory\logs\app-errors-<Datum>.log` | unerwartete Fehler mit Details | vorhanden |
| Scans (Snapshots) | `%LOCALAPPDATA%\SoftwareInventory\scans\<yyyyMMdd-HHmmss-fff>.json` | nur über `Save-InventorySnapshot`; die App speichert keine Scans | vorhanden |
| API-Schlüssel | Windows-Anmeldeinformationsverwaltung oder Umgebungsvariable; **nie** in Einstellungsdateien oder im Repository | NVD, GitHub, KI-Server | vorhanden |
| Richtlinien (Firma) | `HKLM\SOFTWARE\Policies\Softwareverwaltung` (Vorschlag) | vom Administrator festgelegte und gesperrte Einstellungen | geplant (Etappe 6) |

Logs und Zwischenspeicher räumen sich beim Start selbst auf: höchstens 30 Tage alt und höchstens 100 MB insgesamt, beides einstellbar, Ältestes zuerst. Scans sind davon ausgenommen. Alle Dateien liegen unverschlüsselt im Benutzerprofil und sind nur für den Benutzer (und Administratoren) lesbar. Scans und Protokolle können Benutzerpfade und damit den Benutzernamen enthalten.

Deinstallation des Programms: Die Ordner `%LOCALAPPDATA%\SoftwareInventory` und `%APPDATA%\SoftwareInventory` löschen und die Einträge des Programms in der Anmeldeinformationsverwaltung entfernen.

## Netzwerkverbindungen

Eine vollständige Liste mit Datenschutzbewertung steht in [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md). Kurzfassung für Firewall-Freigaben:

| Dienst | Host(s) | Wann | Status |
| --- | --- | --- | --- |
| winget-Quellen | `cdn.winget.microsoft.com` und die Download-Server der Hersteller | beim Lesen der winget-Daten, bei der winget-Suche und bei Aktionen | vorhanden (über winget) |
| GitHub API | `api.github.com` | Versionsabgleich für Programme aus dem Katalog | vorhanden |
| NVD | `services.nvd.nist.gov` | CVE-Abfragen, CPE-Vorschläge | vorhanden |
| CISA KEV | `www.cisa.gov` | Laden der KEV-Liste | vorhanden |
| EPSS | `api.first.org` | Ausnutzungswahrscheinlichkeit für gefundene CVEs | vorhanden |
| Lokaler KI-Server | `localhost:11434` (Ollama), `localhost:1234` (LM Studio), `localhost:8888` (Unsloth Studio) oder eine eigene Adresse | nur wenn der KI-Berater eingerichtet ist | geplant (Etappe 4b) |

Alle Abfragen nutzen die Proxy-Einstellungen des Systems. Jede Anfrage trägt den User-Agent `SoftwareInventory/<Version>`.

## Sicherheitsmerkmale

- Läuft als normaler Benutzer, UAC nur für die einzelne Aktion.
- Der erhöhte Helfer ist ein Skript, dessen SHA256 vor dem Start geprüft wird; das Ergebnis kommt über eine Named Pipe zurück, mit der sich nur erhöhte Prozesse verbinden dürfen (Prozess-ID und Zufallszahl werden geprüft).
- Es wird genau der bestätigte Befehl ausgeführt; hat er sich geändert, bricht die Aktion ohne Ausführung ab.
- Liest Programmdateien nur (PE-Versionsinfo, Signatur, Hash), führt nichts aus.
- KI darf nur vorschlagen; jede Aktion braucht einen Klick und wird protokolliert.
- Vor dem Senden an jedes Modell, auch an lokale, werden Benutzername, Rechnername und Benutzerpfade ersetzt.
- Ergebnisse aus unbestätigten Quellen werden als „unbestätigt“ gekennzeichnet.
- Geplant für den Firmeneinsatz: signierte Skripte und signierte Releases (Authenticode), damit SmartScreen und AppLocker/WDAC-Regeln greifen.

## Telemetrie

Das Projekt selbst sendet keine Telemetrie und soll das auch künftig nicht tun. Zu beachten sind Bestandteile von Microsoft:

- **winget** sendet Nutzungsdaten gemäß den Windows-Diagnoseeinstellungen. Abschaltbar in den winget-Einstellungen (`winget settings`, Abschnitt `"telemetry": { "disable": true }`).
- **PowerShell** kennt Telemetrie; die Umgebungsvariable `POWERSHELL_TELEMETRY_OPTOUT=1` schaltet sie ab. Die App setzt sie vor dem Start der eingebetteten Engine für den ganzen Prozess, der erhöhte Helfer setzt sie als Erstes in seinem Startbefehl. Windows PowerShell 5.1 (Helfer) kennt die Variable nicht; seine Diagnosedaten folgen den Windows-Diagnoseeinstellungen.

## Build und Veröffentlichung

- `.\build\Publish-App.ps1` ruft `dotnet publish -c Release -r win-x64 --self-contained true` auf und legt die App mit eingebetteter .NET-Laufzeit in `artifacts\publish\Softwareverwaltung` und als ZIP in `artifacts\` ab.
- Das Modul `Microsoft.WinGet.Client` (MIT) wird in fester Version mitgeliefert und aus dem App-Ordner geladen. Seine Version wird zusammen mit `Microsoft.PowerShell.SDK` aktualisiert, weil beide dieselbe .NET-/PowerShell-Version voraussetzen (Modul 1.29: .NET 10, PowerShell 7.6). winget selbst (App-Installer) wird nicht mitgeliefert.
- Jedes Release enthält `LICENSE` und `THIRD-PARTY-NOTICES.md` (kopiert das Skript), dazu die Hinweisdateien der eingebetteten Laufzeiten; der passende Quellcode ist über den Git-Tag des Releases verfügbar (GPLv3 § 6).
