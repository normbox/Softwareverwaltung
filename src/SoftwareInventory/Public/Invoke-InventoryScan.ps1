function Invoke-InventoryScan {
    <#
    .SYNOPSIS
        Vollständiger Scan nach den Einstellungen: installierte und, falls eingeschaltet, portable Programme.
    .DESCRIPTION
        Liest die installierten Programme der aktivierten Quellen (Get-SoftwareInventory). Ist der
        Hauptschalter PortableSearch an, sucht es zusätzlich portable Programme (Get-PortableSoftware)
        und gibt dabei die installierten weiter, damit sie nicht doppelt gelesen und ihre Ordner
        ausgelassen werden. Darunter wirken zwei unabhängige Schalter:
          - Nutzungsspuren (TraceSearch): die gewählten Spuren, überall, ohne Laufwerke zu durchsuchen.
          - Dateisuche (FileSearch): nur die Liste der gewählten Option „Wo suchen“ (ganze Laufwerke
            oder bestimmte Ordner, FileScan.Mode). Ohne Option oder mit leerer Liste läuft kein Dateiscan.
        Fehlt etwas, gibt es einen Hinweis (Warnung) statt eines Fehlers; nicht verbundene Laufwerke
        werden übersprungen.
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
    $search = Get-PortableSearchPlan $setting
    if (-not $setting.PortableSearch.TraceSearch -and -not $setting.PortableSearch.FileSearch) {
        Write-Warning (Get-LocalizedString 'PortableSearchNothingSelected')
        return
    }
    if ($setting.PortableSearch.TraceSearch -and -not $search.Trace) { Write-Warning (Get-LocalizedString 'PortableSearchNoTrace') }
    if ($setting.PortableSearch.FileSearch -and -not ($search.Path -or $search.Drive)) { Write-Warning (Get-LocalizedString 'PortableSearchNoLocation') }
    if ($search.Trace -or $search.Path -or $search.Drive) {
        Get-PortableSoftware -Inventory $installed -Trace $search.Trace -Path $search.Path -Drive $search.Drive `
            -IncludeTemp:$setting.FileScan.IncludeTemp -ComputeHash:$setting.FileScan.ComputeHash
    }
}
