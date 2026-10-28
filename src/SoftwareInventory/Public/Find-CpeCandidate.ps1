function Find-CpeCandidate {
    <#
    .SYNOPSIS
        Schlägt CPE-Namen aus dem NVD-Wörterbuch für Programme ohne Katalogeintrag vor (unbestätigt).
    .DESCRIPTION
        Sucht im CPE-Wörterbuch der NVD nach dem bereinigten Programmnamen (ohne Version,
        Architektur und Zusätze in Klammern) und, falls das nichts Passendes liefert, nach dem
        Produktteil der winget-ID (z. B. „Ghisler.TotalCommander“ → „Total Commander“). Die
        Treffer werden nach Hersteller:Produkt zusammengefasst und bewertet, wie gut Produkt
        und Hersteller zum Programm passen. Vorschläge sind ausdrücklich unbestätigt;
        übernommen werden sie erst mit Set-CpeMapping. Benötigt den Dienst NVD.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object Name -like 'GIMP*' | Find-CpeCandidate
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.CpeCandidate')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [ValidateRange(1, 10)] [int] $First = 3
    )
    begin { $setting = Read-InventorySetting }
    process {
        $record = if ($InputObject.PSObject.Properties['Record'] -and $InputObject.Record) { $InputObject.Record } else { $InputObject }
        $queries = @(Get-CpeSearchQuery -Record $record)
        if (-not $queries) { return }

        $found = @{}
        foreach ($query in $queries) {
            try {
                $r = Invoke-ServiceRequest -Service NVD -Setting $setting -CacheKey "cpes/keyword/$query" -MaxAge ([timespan]::FromDays(7)) `
                    -Uri "$script:NvdBase/cpes/2.0?keywordSearch=$([uri]::EscapeDataString($query))&resultsPerPage=500"
            }
            catch {
                Write-Warning (Get-LocalizedString 'WarningCpeSearchFailed' $query, $_.Exception.Message)
                return
            }
            # Veraltete Einträge (deprecated) nicht vorschlagen; nur Anwendungen
            $groups = @($r.products | Where-Object { -not (Get-CatalogValue $_.cpe 'deprecated') } | ForEach-Object { $_.cpe.cpeName } |
                    Where-Object { $_ -match '^cpe:2\.3:a:' } | ForEach-Object { (($_ -split '(?<!\\):')[0..4]) -join ':' } | Group-Object)
            foreach ($g in $groups) {
                if ($found.ContainsKey($g.Name)) { continue }
                $parts = $g.Name -split '(?<!\\):'
                $vendor = $parts[3] -replace '\\', ''
                $product = $parts[4] -replace '\\', ''
                $score = Get-CpeCandidateScore -Vendor $vendor -Product $product -Query $queries -Publisher $record.Publisher
                if ($score -le 0) { continue }
                $found[$g.Name] = [pscustomobject] @{
                    PSTypeName = 'SoftwareInventory.CpeCandidate'
                    Name       = $record.Name
                    Cpe        = $g.Name
                    Vendor     = $vendor
                    Product    = $product
                    Entries    = $g.Count
                    Score      = $score
                    Query      = $query
                    Url        = "https://nvd.nist.gov/products/cpe/search/results?namingFormat=2.3&keyword=$([uri]::EscapeDataString($g.Name))"
                    Confirmed  = $false
                    Record     = $record
                }
            }
            # Weitere Suchbegriffe nur, solange kein Produkt genau passt (spart NVD-Abfragen)
            if ($found.Values | Where-Object Score -ge 3) { break }
        }
        $found.Values | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Entries'; Descending = $true }, Cpe |
            Select-Object -First $First
    }
}
