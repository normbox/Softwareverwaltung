function Invoke-InventoryScan {
    <#
    .SYNOPSIS
        Vollständiger Scan nach den Einstellungen: installierte und, falls aktiviert, portable Programme.
    .DESCRIPTION
        Liest die installierten Programme der aktivierten Quellen (Get-SoftwareInventory). Ist der
        Hauptschalter PortableSearch an und sind Nutzungsspuren, Scan-Ordner oder Laufwerke eingerichtet,
        sucht es zusätzlich portable Programme (Get-PortableSoftware) und gibt dabei die installierten
        weiter, damit sie nicht doppelt gelesen und ihre Ordner ausgelassen werden. Ist die Suche aus
        oder nicht eingerichtet, gibt es dazu keine Warnung; sie ist freiwillig.
    .EXAMPLE
        Invoke-InventoryScan | Get-SecurityRating
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param()

    $installed = @(Get-SoftwareInventory)
    foreach ($record in $installed) { $record }
    if (Test-PortableScanEnabled (Read-InventorySetting)) {
        Get-PortableSoftware -Inventory $installed
    }
}

function Test-PortableScanEnabled {
    # Hauptschalter an und Suche eingerichtet (Spuren, Ordner oder Laufwerke)?
    param($Setting)
    if (-not $Setting.PortableSearch.Enabled) { return $false }
    [bool] (@(Get-EnabledName $Setting.Traces) + @($Setting.FileScan.Paths | Where-Object { $_ }) + @($Setting.FileScan.Drives | Where-Object { $_ }))
}
