function Get-SoftwareInventory {
    <#
    .SYNOPSIS
        Erfasst die installierte Software dieses Rechners.
    .DESCRIPTION
        Liest Registry (Rechner und aktueller Benutzer), Store-Apps und winget und
        liefert einen Datensatz pro Programm. Benötigt keine Administratorrechte.
        Fällt eine Quelle aus, wird gewarnt und mit den übrigen weitergemacht.
    .PARAMETER Source
        Zu lesende Quellen; Standard sind alle.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object AvailableVersion
    .EXAMPLE
        Get-SoftwareInventory -Source Registry | Format-Table Name, Version, Scope
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [ValidateSet('Registry', 'Winget', 'Appx')]
        [string[]] $Source = @('Registry', 'Winget', 'Appx')
    )

    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        Write-Warning '32-Bit-Prozess auf 64-Bit-Windows: 64-Bit-Programme in der Registry fehlen.'
    }

    $base = @()
    if ('Registry' -in $Source) { $base += @(Get-RegistrySoftware) }
    if ('Appx' -in $Source) { $base += @(Get-AppxSoftware) }
    $winget = if ('Winget' -in $Source) { @(Get-WingetSoftware) } else { @() }

    Merge-SoftwareRecord -BaseRecord $base -WingetRecord $winget
}
