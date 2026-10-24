# Entwicklung

## Einrichtung

```powershell
winget install --id Microsoft.PowerShell --exact          # PowerShell 7.6 LTS
pwsh -c "Install-PSResource Pester,PSScriptAnalyzer,Microsoft.WinGet.Client -Scope CurrentUser -TrustRepository"
winget install Microsoft.DotNet.SDK.10                    # ab Etappe 3
```

Das Modul zielt auf PowerShell 7 (die Engine, die die App über `Microsoft.PowerShell.SDK` einbettet). Windows PowerShell 5.1 wird nicht unterstützt.

## Tests

```powershell
pwsh -c "Invoke-Pester ./tests/Unit"                     # Unit-Tests
pwsh -c "Invoke-Pester ./tests/Integration"              # gegen das echte System
pwsh -c "Invoke-ScriptAnalyzer ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
```

## Machbarkeitsprüfung (24.10.2026)

Getestet mit PowerShell 7.6.8, einmal in `pwsh` und einmal eingebettet in eine .NET-10-Konsolen-App mit `Microsoft.PowerShell.SDK` 7.6.8:

| Quelle | pwsh | eingebettet |
| --- | --- | --- |
| Registry (Uninstall-Schlüssel) | ok | ok |
| `Get-AppxPackage` (ohne `-UseWindowsPowerShell`) | ok | ok |
| `Get-WinGetPackage` (Microsoft.WinGet.Client 1.29) | ok | ok |

Folgerungen:

- Kein Ersatzweg über die Textausgabe von `winget list`. Fehlt das Modul, meldet das Inventar „winget nicht verfügbar“ und liefert die übrigen Quellen.
- winget-Pakete lassen sich über `GetPackageVersionInfo(...).ProductCodes` den Registry-Einträgen zuordnen (enthält Schlüsselnamen und MSI-GUIDs). Einträge ohne Katalogtreffer tragen IDs wie `ARP\Machine\X64\<Schlüssel>` bzw. `MSIX\<PackageFullName>`.
- Für Etappe 3 merken: Die App muss `Microsoft.WinGet.Client` mitliefern, da es beim Nutzer nicht installiert sein muss.

## Machbarkeitsprüfung Etappe 2 (24.10.2026)

Abgefragt ohne API-Schlüssel und ohne Token; gesendet wurden nur Produktnamen, CPEs und CVE-IDs.

| Prüfung | Ergebnis |
| --- | --- |
| NVD `cves/2.0?cpeName=…:7-zip:7-zip:24.08:…` | 14 CVEs, darunter CVE-2025-0411, obwohl die NVD dort nur `versionEndExcluding 24.09` einträgt. NVD wertet Versionsbereiche selbst aus. |
| dieselbe Abfrage mit Version `24.08.5` (nicht im CPE-Wörterbuch) | ebenfalls 14 CVEs; die Version muss nicht im Wörterbuch stehen |
| NVD `cpes/2.0?keywordSearch=` | brauchbar als Vorschlag: VLC eindeutig (`videolan:vlc_media_player`), Notepad++ mit drei Hersteller-Schreibweisen, „Python“ über 22.000 Treffer. Ergebnis daher nur als unbestätigter Vorschlag. |
| CISA KEV (JSON-Feed) | 1.756 Einträge, ca. 1 s; Felder u. a. `cveID`, `dateAdded`, `knownRansomwareCampaignUse` |
| EPSS (`api.first.org/data/v1/epss?cve=a,b,c`) | Sammelabfrage funktioniert; `epss` und `percentile` als Zahl in Textform |
| GitHub `releases/latest` ohne Token | 60 Anfragen pro Stunde; Tags mit Präfix (`v8.9.8.1`) |

Folgerungen:

- Für die CVE-Suche reicht `cpeName` mit der installierten Version; das Modul muss Versionsbereiche nicht selbst auswerten.
- Ohne NVD-Schlüssel höchstens 5 Anfragen pro 30 s, mit Schlüssel 50. Der Schlüssel ist optional und darf nie in Protokollen, Snapshots oder Berichten erscheinen.
- Zeitangaben aus Feeds mit `ConvertFrom-Json -DateKind String` lesen (sonst wandelt PowerShell sie in Ortszeit um).
- Versionsnormalisierung muss Präfixe wie `v` und Zusätze nach der Versionsnummer entfernen.
