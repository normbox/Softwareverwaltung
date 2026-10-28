# Einstellungen: Jeder Scan-Bereich ist standardmäßig aus und wird vom Benutzer einzeln
# aktiviert (siehe CLAUDE.md „Alles manuell einstellbar“). Usage ist reine Information.

$script:SettingsSchemaVersion = 1
$script:InstalledSources = @('RegistryMachine', 'RegistryUser', 'Winget', 'Appx')
$script:TraceSources = @('UserAssist', 'Process', 'Autostart', 'ScheduledTask')
# Externe Dienste: senden Produkt-/Herstellernamen, Versionen oder CVE-IDs ins Internet.
# Werden nur einzeln aktiviert, nie über eine Vorlage.
$script:ServiceSources = @('WingetSearch', 'GitHub', 'NVD', 'KEV', 'EPSS')
# Optionen für Aktualisieren/Deinstallieren; ebenfalls standardmäßig aus.
$script:ActionOptions = @('RestorePoint')
# KI-Berater: nur lokale Server mit OpenAI-kompatibler Schnittstelle (Etappe 4). Vorgaben sind
# Standardadressen bekannter Programme; die Adresse bleibt änderbar. Kein Standardmodell.
# Produktnamen sind keine Übersetzungstexte; Hinweise und „Eigene Adresse“ stehen in den Texten
# (AdvisorPresetNote<Name>, AdvisorPresetLabelCustom).
$script:AdvisorPresets = [ordered]@{
    Ollama   = @{ Label = 'Ollama'; Endpoint = 'http://localhost:11434/v1'; RequiresApiKey = $false }
    LMStudio = @{ Label = 'LM Studio'; Endpoint = 'http://localhost:1234/v1'; RequiresApiKey = $false }
    Unsloth  = @{ Label = 'Unsloth Studio'; Endpoint = 'http://localhost:8888/v1'; RequiresApiKey = $true }
    Custom   = @{ Label = $null; Endpoint = $null; RequiresApiKey = $false }
}
# Selbstbereinigung von Logs und Zwischenspeicher (siehe CLAUDE.md); Grenzen einstellbar.
$script:DefaultLogRetentionDays = 30
$script:DefaultLogMaxSizeMB = 100
# Haltbarkeit des Zwischenspeichers je Quelle in Stunden (1–720); LatestVersion gilt für GitHub und winget-Suche.
$script:DefaultCacheHours = [ordered]@{ LatestVersion = 6; NVD = 24; EPSS = 24; KEV = 24 }

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
    $actions = [ordered]@{}
    foreach ($a in $script:ActionOptions) { $actions[$a] = $false }

    [pscustomobject] [ordered]@{
        PSTypeName    = 'SoftwareInventory.Setting'
        SchemaVersion = $script:SettingsSchemaVersion
        Usage         = $null   # Private oder Company; schaltet nichts
        Sources       = [pscustomobject] $sources
        Traces        = [pscustomobject] $traces
        Services      = [pscustomobject] $services
        Actions       = [pscustomobject] $actions   # RestorePoint: vor jeder Aktion Wiederherstellungspunkt (UAC)
        Maintenance   = [pscustomobject] [ordered]@{
            LogRetentionDays = $script:DefaultLogRetentionDays
            LogMaxSizeMB     = $script:DefaultLogMaxSizeMB
        }
        CacheHours    = [pscustomobject] ([ordered]@{} + $script:DefaultCacheHours)
        Advisor       = [pscustomobject] [ordered]@{
            Enabled  = $false   # KI-Berater; standardmäßig aus
            Preset   = $null    # Ollama, LMStudio, Unsloth oder Custom
            Endpoint = $null    # Basisadresse der OpenAI-kompatiblen Schnittstelle, z. B. http://localhost:11434/v1
            Model    = $null    # vom Benutzer aus den installierten Modellen gewählt; kein Standard
        }
        # Hauptschalter für die Suche nach portablen Programmen im vollständigen Scan (Invoke-InventoryScan).
        # Aus = keine Suche; Nutzungsspuren und FileScan bleiben gespeichert. Keine Vorlage schaltet ihn ein.
        # Darunter zwei eigene Schalter: Nutzungsspuren (TraceSearch) und Dateisuche (FileSearch), beide standardmäßig aus.
        PortableSearch = [pscustomobject] [ordered]@{ Enabled = $false; TraceSearch = $false; FileSearch = $false }
        FileScan      = [pscustomobject] [ordered]@{
            Mode            = $null            # „Wo suchen“: Drives oder Folders; nur diese Liste wird genutzt, die andere bleibt gespeichert
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
        Write-Warning (Get-LocalizedString 'WarningSettingsUnreadable' $path, $_.Exception.Message)
        return $setting
    }

    if ($data.PSObject.Properties['Usage'] -and $data.Usage -in 'Private', 'Company') { $setting.Usage = $data.Usage }
    foreach ($group in 'Sources', 'Traces', 'Services', 'Actions') {
        if (-not $data.PSObject.Properties[$group]) { continue }
        foreach ($name in $setting.$group.PSObject.Properties.Name) {
            $value = $data.$group.PSObject.Properties[$name]
            if ($value) { $setting.$group.$name = [bool] $value.Value }
        }
    }
    if ($data.PSObject.Properties['Maintenance']) {
        foreach ($name in 'LogRetentionDays', 'LogMaxSizeMB') {
            $value = $data.Maintenance.PSObject.Properties[$name]
            if ($value -and ($value.Value -as [int]) -ge 1) { $setting.Maintenance.$name = [int] $value.Value }
        }
    }
    if ($data.PSObject.Properties['CacheHours'] -and $data.CacheHours) {
        foreach ($name in @($script:DefaultCacheHours.Keys)) {
            $value = $data.CacheHours.PSObject.Properties[$name]
            $hours = if ($value) { $value.Value -as [int] }
            if ($hours -ge 1 -and $hours -le 720) { $setting.CacheHours.$name = $hours }
        }
    }
    if ($data.PSObject.Properties['PortableSearch'] -and $data.PortableSearch) {
        foreach ($name in 'Enabled', 'TraceSearch', 'FileSearch') {
            if ($data.PortableSearch.PSObject.Properties[$name]) { $setting.PortableSearch.$name = [bool] $data.PortableSearch.$name }
        }
    }
    if ($data.PSObject.Properties['Advisor'] -and $data.Advisor) {
        $a = $data.Advisor
        if ($a.PSObject.Properties['Enabled']) { $setting.Advisor.Enabled = [bool] $a.Enabled }
        if ($a.PSObject.Properties['Preset'] -and $a.Preset -in $script:AdvisorPresets.Keys) { $setting.Advisor.Preset = [string] $a.Preset }
        if ($a.PSObject.Properties['Endpoint'] -and (Test-AdvisorEndpoint ([string] $a.Endpoint))) { $setting.Advisor.Endpoint = ([string] $a.Endpoint).TrimEnd('/') }
        if ($a.PSObject.Properties['Model'] -and $a.Model) { $setting.Advisor.Model = [string] $a.Model }
    }
    if ($data.PSObject.Properties['FileScan']) {
        $fs = $data.FileScan
        if ($fs.PSObject.Properties['Paths']) { $setting.FileScan.Paths = [string[]] @($fs.Paths | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['Drives']) { $setting.FileScan.Drives = [string[]] @($fs.Drives | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['IncludeTemp']) { $setting.FileScan.IncludeTemp = [bool] $fs.IncludeTemp }
        if ($fs.PSObject.Properties['ComputeHash']) { $setting.FileScan.ComputeHash = [bool] $fs.ComputeHash }
        if ($fs.PSObject.Properties['ExcludePaths']) { $setting.FileScan.ExcludePaths = [string[]] @($fs.ExcludePaths | Where-Object { $_ }) }
        if ($fs.PSObject.Properties['SmartExclusions'] -and $null -ne $fs.SmartExclusions) { $setting.FileScan.SmartExclusions = [bool] $fs.SmartExclusions }
        if ($fs.PSObject.Properties['Mode']) {
            if ($fs.Mode -in 'Drives', 'Folders') { $setting.FileScan.Mode = [string] $fs.Mode }
        }
        # Ältere Datei ohne Mode: Ordner vorhanden → nur Ordner (schneller), sonst Laufwerke vorhanden → Laufwerke.
        elseif ($setting.FileScan.Paths) { $setting.FileScan.Mode = 'Folders' }
        elseif ($setting.FileScan.Drives) { $setting.FileScan.Mode = 'Drives' }
    }
    $setting
}

function Write-InventorySetting {
    param([Parameter(Mandatory)] $Setting)
    $path = Get-SettingsPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    $Setting | Select-Object SchemaVersion, Usage, Sources, Traces, Services, Actions, Maintenance, Advisor, PortableSearch, FileScan |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
}

function Get-PortableSearchPlan {
    # Was die Suche nach portablen Programmen tatsächlich nutzt, nach den Unterschaltern
    # Nutzungsspuren und Dateisuche (der Hauptschalter wird vom Aufrufer geprüft).
    param($Setting)
    $active = Get-ActiveScanLocation $Setting
    [pscustomobject] @{
        Trace = [string[]] @(if ($Setting.PortableSearch.TraceSearch) { Get-EnabledName $Setting.Traces })
        Path  = [string[]] @(if ($Setting.PortableSearch.FileSearch) { $active.Paths })
        Drive = [string[]] @(if ($Setting.PortableSearch.FileSearch) { $active.Drives })
    }
}

function Get-ActiveScanLocation {
    # Ordner und Laufwerke, die tatsächlich durchsucht werden: nur die Liste der gewählten Option.
    param($Setting)
    [pscustomobject] @{
        Paths  = [string[]] @(if ($Setting.FileScan.Mode -eq 'Folders') { $Setting.FileScan.Paths | Where-Object { $_ } })
        Drives = [string[]] @(if ($Setting.FileScan.Mode -eq 'Drives') { $Setting.FileScan.Drives | Where-Object { $_ } })
    }
}

function Test-AdvisorEndpoint {
    # Nur absolute http(s)-Adressen ohne Benutzerdaten in der URL.
    param([AllowNull()] [AllowEmptyString()] [string] $Endpoint)
    if (-not $Endpoint) { return $false }
    $uri = $null
    [uri]::TryCreate($Endpoint, [UriKind]::Absolute, [ref] $uri) -and $uri.Scheme -in 'http', 'https' -and -not $uri.UserInfo
}

function Get-EnabledName {
    # Namen der eingeschalteten Werte einer Gruppe (Sources, Traces, Services oder Actions).
    param($Group)
    $Group.PSObject.Properties | Where-Object Value | ForEach-Object Name
}

function Test-ServiceEnabled {
    # Ist der externe Dienst in den Einstellungen aktiviert?
    param([Parameter(Mandatory)] [string] $Name, $Setting = (Read-InventorySetting))
    [bool] $Setting.Services.$Name
}
