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
