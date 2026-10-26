function Invoke-InventoryScan {
    <#
    .SYNOPSIS
        Vollständiger Scan nach den Einstellungen: installierte und, falls aktiviert, portable Programme.
    .DESCRIPTION
        Liest die installierten Programme der aktivierten Quellen (Get-SoftwareInventory). Sind
        Nutzungsspuren, Scan-Ordner oder Laufwerke aktiviert, sucht es zusätzlich portable Programme
        (Get-PortableSoftware) und gibt dabei die installierten weiter, damit sie nicht doppelt gelesen
        und ihre Ordner ausgelassen werden. Ist die Suche nach portablen Programmen nicht eingerichtet,
        gibt es dazu keine Warnung; sie ist freiwillig.
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
    # Ist die Suche nach portablen Programmen eingerichtet (Spuren, Ordner oder Laufwerke)?
    param($Setting)
    [bool] (@(Get-EnabledName $Setting.Traces) + @($Setting.FileScan.Paths | Where-Object { $_ }) + @($Setting.FileScan.Drives | Where-Object { $_ }))
}
