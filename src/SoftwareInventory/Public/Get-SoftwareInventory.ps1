function Get-SoftwareInventory {
    <#
    .SYNOPSIS
        Erfasst die installierte Software dieses Rechners.
    .DESCRIPTION
        Liest nur die Quellen, die in den Einstellungen aktiviert sind (Set-InventorySetting)
        oder ausdrücklich mit -Source angegeben werden. Standardmäßig ist nichts aktiviert.
        Liefert einen Datensatz pro Programm. Benötigt keine Administratorrechte.
        Fällt eine Quelle aus, wird gewarnt und mit den übrigen weitergemacht.
    .PARAMETER Source
        RegistryMachine (HKLM, 64- und 32-Bit), RegistryUser (HKCU), Winget, Appx.
        Überschreibt für diesen Aufruf die Einstellungen.
    .EXAMPLE
        Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx
        Get-SoftwareInventory | Where-Object AvailableVersion
    .EXAMPLE
        Get-SoftwareInventory -Source RegistryUser | Format-Table Name, Version
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [ValidateSet('RegistryMachine', 'RegistryUser', 'Winget', 'Appx')]
        [string[]] $Source
    )

    if (-not $PSBoundParameters.ContainsKey('Source')) {
        $Source = @(Get-EnabledName (Read-InventorySetting).Sources)
    }
    if (-not $Source) {
        Write-Warning (Get-LocalizedString 'WarningNoSourceEnabled')
        return
    }

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Warning (Get-LocalizedString 'WarningWow64')
    }

    $base = @()
    $locations = @(Get-DefaultUninstallLocation | Where-Object {
            ($_.Scope -eq 'Machine' -and 'RegistryMachine' -in $Source) -or ($_.Scope -eq 'User' -and 'RegistryUser' -in $Source)
        })
    if ($locations) { $base += @(Get-RegistrySoftware -Location $locations) }
    if ('Appx' -in $Source) { $base += @(Get-AppxSoftware) }
    $winget = if ('Winget' -in $Source) { @(Get-WingetSoftware) } else { @() }

    Merge-SoftwareRecord -BaseRecord $base -WingetRecord $winget
}
