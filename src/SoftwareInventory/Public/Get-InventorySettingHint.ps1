function Get-InventorySettingHint {
    <#
    .SYNOPSIS
        Hinweise zu Einstellungen, die sich gegenseitig beeinflussen (Code, Args, Text).
    .DESCRIPTION
        CacheLongerThanGreenMaxAge: Die Haltbarkeit (CacheHours) von NVD, CIRCL oder KEV liegt über dem
        Höchstalter für Grün. Dann werden Programme grau, sobald die gespeicherten Daten älter sind, obwohl
        sie noch nicht neu abgefragt werden. EPSS zählt nicht, weil es die Ampel nicht beeinflusst.
        Ohne -Setting gelten die gespeicherten Einstellungen.
    .EXAMPLE
        Get-InventorySettingHint | ForEach-Object Text
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.Message')]
    param(
        # Einstellungen wie von Get-InventorySetting; ohne Angabe die gespeicherten
        $Setting
    )
    if (-not $Setting) { $Setting = Read-InventorySetting }
    $days = Get-GreenMaxAgeDay $Setting
    $long = @('NVD', 'CIRCL', 'KEV' | Where-Object { (Get-CacheMaxAge -Service $_ -Setting $Setting).TotalDays -gt $days })
    if ($long) { New-InventoryMessage CacheLongerThanGreenMaxAge ($long -join ', '), $days }
}
