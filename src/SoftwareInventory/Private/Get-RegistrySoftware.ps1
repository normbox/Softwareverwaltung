function Get-DefaultUninstallLocation {
    # Die App läuft als 64-Bit-Prozess; dann zeigt HKLM:\SOFTWARE auf die native Ansicht.
    $native = [string] [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $uninstall = 'Microsoft\Windows\CurrentVersion\Uninstall'
    @(
        @{ Path = "HKLM:\SOFTWARE\$uninstall";             Scope = 'Machine'; Architecture = $native }
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\$uninstall"; Scope = 'Machine'; Architecture = 'X86' }
        @{ Path = "HKCU:\SOFTWARE\$uninstall";             Scope = 'User';    Architecture = $null }
    )
}

function Get-RegistrySoftware {
    <#
    .SYNOPSIS
        Liest installierte Programme aus den Uninstall-Schlüsseln der Registry.
    .DESCRIPTION
        Filtert Systemkomponenten, Windows-Updates und Unterpakete heraus.
        -Location ist für Tests gedacht; Standard sind HKLM (nativ und WOW6432Node) und HKCU.
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [hashtable[]] $Location = (Get-DefaultUninstallLocation)
    )

    foreach ($loc in $Location) {
        if (-not (Test-Path -LiteralPath $loc.Path)) {
            Write-Verbose "Registry-Pfad nicht vorhanden: $($loc.Path)"
            continue
        }

        foreach ($key in Get-ChildItem -LiteralPath $loc.Path -ErrorAction SilentlyContinue) {
            ConvertFrom-UninstallKey -Key $key -Location $loc
        }
    }
}

function ConvertFrom-UninstallKey {
    # Datensatz aus einem Uninstall-Schlüssel; nichts, wenn der Eintrag kein eigenständiges Programm ist.
    param([Parameter(Mandatory)] $Key, [Parameter(Mandatory)] [hashtable] $Location)
            $key = $Key
            $loc = $Location
            $name = [string] $key.GetValue('DisplayName')
            if (-not (Test-RegistryEntryIsProgram -Key $key -DisplayName $name)) { return }

            $keyName = $key.PSChildName
            $isMsi = $key.GetValue('WindowsInstaller') -eq 1

            $record = New-SoftwareRecord -Name $name.Trim() -Source Registry -Property @{
                Publisher            = ConvertTo-NullIfEmpty $key.GetValue('Publisher')
                Version              = ConvertTo-NullIfEmpty $key.GetValue('DisplayVersion')
                InstallType          = if ($isMsi) { 'MSI' } else { 'EXE' }
                Scope                = $loc.Scope
                Architecture         = $loc.Architecture
                ProductCode          = if ($isMsi -and $keyName -match '^\{[0-9A-Fa-f-]{36}\}$') { $keyName.ToUpperInvariant() } else { $null }
                RegistryKey          = "$($loc.Path)\$keyName"
                InstallLocation      = ConvertTo-NullIfEmpty $key.GetValue('InstallLocation')
                InstallDate          = ConvertFrom-RegistryDate $key.GetValue('InstallDate')
                UninstallString      = ConvertTo-NullIfEmpty $key.GetValue('UninstallString')
                QuietUninstallString = ConvertTo-NullIfEmpty $key.GetValue('QuietUninstallString')
                DisplayIcon          = ConvertFrom-DisplayIcon $key.GetValue('DisplayIcon')
            }
            # Verwaister Rest: Deinstaller, Installationsordner und Symbol zeigen ins Leere (Fall Jan 0.5.16)
            if (Test-OrphanedRegistryEntry -Record $record -IsMsi $isMsi) { $record.Flags = [string[]] @('Orphaned') }
            Add-MatchKey -Record $record -Key @(
                "arp:$keyName".ToLowerInvariant()
                "arp:$($loc.Scope):$keyName".ToLowerInvariant()
            )   # gibt den Datensatz aus
}

function Test-RegistryEntryIsProgram {
    # Entscheidet, ob ein Uninstall-Eintrag ein eigenständiges Programm ist.
    param($Key, [string] $DisplayName)

    if ([string]::IsNullOrWhiteSpace($DisplayName)) { return $false }
    if ($Key.GetValue('SystemComponent') -eq 1) { return $false }
    if ($Key.GetValue('ParentKeyName') -or $Key.GetValue('ParentDisplayName')) { return $false }
    if ($Key.GetValue('ReleaseType') -in 'Update', 'Hotfix', 'Security Update', 'Update Rollup', 'Service Pack') { return $false }
    if ($DisplayName -match '\(KB\d{6,8}\)') { return $false }
    $true
}

function ConvertTo-NullIfEmpty {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = ([string] $Value).Trim()
    if ($text) { $text } else { $null }
}

function ConvertFrom-RegistryDate {
    # InstallDate steht meist als yyyyMMdd in der Registry; alles andere wird verworfen.
    param($Value)
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParseExact([string] $Value, 'yyyyMMdd', [cultureinfo]::InvariantCulture, 'None', [ref] $parsed)) {
        $parsed.ToString('yyyy-MM-dd')
    }
}

function ConvertFrom-DisplayIcon {
    # "C:\Programme\App\app.exe",0 -> C:\Programme\App\app.exe
    param($Value)
    $text = ConvertTo-NullIfEmpty $Value
    if (-not $text) { return $null }
    $text = ($text -replace ',\s*-?\d+$', '').Trim('"', ' ')
    [Environment]::ExpandEnvironmentVariables($text)
}

function Get-PathState {
    <#
    .SYNOPSIS
        Exists, Missing oder Unknown für einen Pfad aus der Registry (Anführungszeichen und Umgebungsvariablen erlaubt).
    .DESCRIPTION
        Unknown bei leeren Angaben, Netzwerkpfaden und Laufwerken, die gerade nicht erreichbar sind: Dort lässt
        sich nicht sagen, ob etwas fehlt.
    #>
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return 'Unknown' }
    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"').Trim())
    if (-not $p -or $p.StartsWith('\\') -or -not [System.IO.Path]::IsPathRooted($p)) { return 'Unknown' }
    if (-not (Test-PathRootReachable $p)) { return 'Unknown' }
    if (Test-Path -LiteralPath $p) { 'Exists' } else { 'Missing' }
}

function Test-OrphanedRegistryEntry {
    <#
    .SYNOPSIS
        Ist der Uninstall-Eintrag nur noch ein Rest ohne Programm?
    .DESCRIPTION
        Verwaist nur, wenn die Datei im Deinstallationsbefehl (UninstallString und QuietUninstallString) fehlt
        und InstallLocation sowie DisplayIcon fehlen oder ins Leere zeigen. Geprüft werden die genannten Dateien
        und Ordner selbst, nicht übergeordnete Ordner (bei Jan 0.5.16 gibt es …\Programs\jan noch, weil es der
        Ordner der neuen Installation ist). Nie verwaist: MSI-Einträge (entscheidet Windows Installer), Einträge
        ohne Deinstallationsbefehl, nicht auswertbare Befehle, Systemwerkzeuge (rundll32, msiexec …),
        Netzwerkpfade und nicht erreichbare Laufwerke.
    #>
    param($Record, [bool] $IsMsi)
    if ($IsMsi) { return $false }
    $commands = @($Record.UninstallString, $Record.QuietUninstallString) | Where-Object { $_ }
    if (-not $commands) { return $false }
    $system = @([Environment]::GetFolderPath('System'), [Environment]::GetFolderPath('SystemX86'), $env:WINDIR) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }
    foreach ($command in $commands) {
        $parts = Split-CommandLine $command
        if ($parts.Error -or -not $parts.FilePath) { return $false }
        if ($system | Where-Object { $parts.FilePath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) { return $false }
        if ((Get-PathState $parts.FilePath) -ne 'Missing') { return $false }
    }
    foreach ($path in $Record.InstallLocation, $Record.DisplayIcon) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ((Get-PathState $path) -ne 'Missing') { return $false }
    }
    $true
}
