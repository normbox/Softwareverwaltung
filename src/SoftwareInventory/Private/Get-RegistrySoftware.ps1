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
            $name = [string] $key.GetValue('DisplayName')
            if (-not (Test-RegistryEntryIsProgram -Key $key -DisplayName $name)) { continue }

            $keyName = $key.PSChildName
            $isMsi = $key.GetValue('WindowsInstaller') -eq 1

            New-SoftwareRecord -Name $name.Trim() -Source Registry -Property @{
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
            }
        }
    }
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
