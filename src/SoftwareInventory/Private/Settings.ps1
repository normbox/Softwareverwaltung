# Einstellungen: Jeder Scan-Bereich ist standardmäßig aus und wird vom Benutzer einzeln
# aktiviert (siehe CLAUDE.md „Alles manuell einstellbar“). Usage ist reine Information.

$script:SettingsSchemaVersion = 1
$script:InstalledSources = @('RegistryMachine', 'RegistryUser', 'Winget', 'Appx')
$script:TraceSources = @('UserAssist', 'Process', 'Autostart', 'ScheduledTask')
# Externe Dienste: senden Produkt-/Herstellernamen, Versionen oder CVE-IDs ins Internet.
# Werden nur einzeln aktiviert, nie über eine Vorlage.
$script:ServiceSources = @('WingetSearch', 'GitHub', 'NVD', 'KEV', 'EPSS')

function Get-SettingsPath {
    Join-Path $env:APPDATA 'SoftwareInventory\settings.json'
}

function New-DefaultSetting {
    $sources = [ordered]@{}
    foreach ($s in $script:InstalledSources) { $sources[$s] = $false }
    $traces = [ordered]@{}
    foreach ($t in $script:TraceSources) { $traces[$t] = $false }
    $services = [ordered]@{}
    foreach ($s in $script:ServiceSources) { $services[$s] = $false }

    [pscustomobject] [ordered]@{
        PSTypeName    = 'SoftwareInventory.Setting'
        SchemaVersion = $script:SettingsSchemaVersion
        Usage         = $null   # Private oder Company; schaltet nichts
        Sources       = [pscustomobject] $sources
        Traces        = [pscustomobject] $traces
        Services      = [pscustomobject] $services
        FileScan      = [pscustomobject] [ordered]@{
            Paths           = [string[]] @()   # Umgebungsvariablen erlaubt, z. B. %USERPROFILE%
            Drives          = [string[]] @()
            IncludeTemp     = $false
            ComputeHash     = $false
            ExcludePaths    = [string[]] @()   # eigene Ausschlüsse für Dateiscan und Spuren
            SmartExclusions = $true            # Herstellerordner-Regel und Abgleich über Name/Version
        }
    }
}

function Read-InventorySetting {
    # Liest die Datei und ergänzt fehlende Werte mit „aus“; unbekannte Werte werden ignoriert.
    $setting = New-DefaultSetting
    $path = Get-SettingsPath
    if (-not (Test-Path -LiteralPath $path)) { return $setting }

    try {
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Einstellungen nicht lesbar ($path), es gilt: alles aus. $_"
        return $setting
    }

    if ($data.PSObject.Properties['Usage'] -and $data.Usage -in 'Private', 'Company') { $setting.Usage = $data.Usage }
    foreach ($group in 'Sources', 'Traces', 'Services') {
        if (-not $data.PSObject.Properties[$group]) { continue }
        foreach ($name in $setting.$group.PSObject.Properties.Name) {
            $value = $data.$group.PSObject.Properties[$name]
            if ($value) { $setting.$group.$name = [bool] $value.Value }
        }
    }
    if ($data.PSObject.Properties['FileScan']) {
        $fs = $data.FileScan
        if ($fs.PSObject.Properties['Paths']) { $setting.FileScan.Paths = [string[]] @($fs.Paths | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['Drives']) { $setting.FileScan.Drives = [string[]] @($fs.Drives | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['IncludeTemp']) { $setting.FileScan.IncludeTemp = [bool] $fs.IncludeTemp }
        if ($fs.PSObject.Properties['ComputeHash']) { $setting.FileScan.ComputeHash = [bool] $fs.ComputeHash }
        if ($fs.PSObject.Properties['ExcludePaths']) { $setting.FileScan.ExcludePaths = [string[]] @($fs.ExcludePaths | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['SmartExclusions'] -and $null -ne $fs.SmartExclusions) { $setting.FileScan.SmartExclusions = [bool] $fs.SmartExclusions }
    }
    $setting
}

function Write-InventorySetting {
    param([Parameter(Mandatory)] $Setting)
    $path = Get-SettingsPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    $Setting | Select-Object SchemaVersion, Usage, Sources, Traces, Services, FileScan |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
}

function Get-EnabledName {
    # Namen der eingeschalteten Werte einer Gruppe (Sources, Traces oder Services).
    param($Group)
    $Group.PSObject.Properties | Where-Object Value | ForEach-Object Name
}

function Test-ServiceEnabled {
    # Ist der externe Dienst in den Einstellungen aktiviert?
    param([Parameter(Mandatory)] [string] $Name, $Setting = (Read-InventorySetting))
    [bool] $Setting.Services.$Name
}
