function Invoke-InventoryScan {
    <#
    .SYNOPSIS
        Vollständiger Scan nach den Einstellungen: installierte und, falls eingeschaltet, portable Programme.
    .DESCRIPTION
        Liest die installierten Programme der aktivierten Quellen (Get-SoftwareInventory). Ist der
        Hauptschalter PortableSearch an, sucht es zusätzlich portable Programme (Get-PortableSoftware)
        und gibt dabei die installierten weiter, damit sie nicht doppelt gelesen und ihre Ordner
        ausgelassen werden:
          - Dateien werden nur in der Liste der gewählten Option „Wo suchen“ durchsucht (ganze
            Laufwerke oder bestimmte Ordner, FileScan.Mode). Ohne Option oder mit leerer Liste läuft
            kein Dateiscan, und es gibt einen Hinweis (Warnung).
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
    $active = Get-ActiveScanLocation $setting
    $hasLocation = [bool] (@($active.Paths) + @($active.Drives))
    if (-not $hasLocation) {
        Write-Warning (Get-LocalizedString $(if ($traces) { 'PortableSearchNoLocation' } else { 'PortableSearchNothingSelected' }))
    }
    if ($hasLocation -or $traces) {
        Get-PortableSoftware -Inventory $installed
    }
}
