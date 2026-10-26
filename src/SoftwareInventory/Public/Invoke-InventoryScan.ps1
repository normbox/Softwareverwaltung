function Invoke-InventoryScan {
    <#
    .SYNOPSIS
        Vollständiger Scan nach den Einstellungen: installierte und, falls eingeschaltet, portable Programme.
    .DESCRIPTION
        Liest die installierten Programme der aktivierten Quellen (Get-SoftwareInventory). Ist der
        Hauptschalter PortableSearch an, sucht es zusätzlich portable Programme (Get-PortableSoftware)
        und gibt dabei die installierten weiter, damit sie nicht doppelt gelesen und ihre Ordner
        ausgelassen werden:
          - Dateien werden nur auf den gewählten Laufwerken und in den gewählten Ordnern durchsucht.
            Ohne Auswahl läuft kein Dateiscan, und es gibt einen Hinweis (Warnung).
          - Eingeschaltete Nutzungsspuren wirken unabhängig von dieser Auswahl.
        Ist der Hauptschalter aus, wird nicht gesucht und nichts gemeldet; die Suche ist freiwillig.
    .EXAMPLE
        Invoke-InventoryScan | Get-SecurityRating
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param()

    $installed = @(Get-SoftwareInventory)
    foreach ($record in $installed) { $record }

    $setting = Read-InventorySetting
    if (-not $setting.PortableSearch.Enabled) { return }
    $traces = @(Get-EnabledName $setting.Traces)
    $hasLocation = [bool] (@($setting.FileScan.Paths | Where-Object { $_ }) + @($setting.FileScan.Drives | Where-Object { $_ }))
    if (-not $hasLocation) {
        Write-Warning (Get-LocalizedString $(if ($traces) { 'PortableSearchNoLocation' } else { 'PortableSearchNothingSelected' }))
    }
    if ($hasLocation -or $traces) {
        Get-PortableSoftware -Inventory $installed
    }
}
