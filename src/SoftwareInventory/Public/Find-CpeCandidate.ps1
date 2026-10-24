function Find-CpeCandidate {
    <#
    .SYNOPSIS
        Schlägt CPE-Namen aus dem NVD-Wörterbuch für Programme ohne Katalogeintrag vor (unbestätigt).
    .DESCRIPTION
        Sucht im CPE-Wörterbuch der NVD nach dem Programmnamen (ohne Versionsangabe) und fasst
        die Treffer nach Hersteller:Produkt zusammen. Bewertet wird, wie gut Produkt und
        Hersteller zum Programm passen. Vorschläge sind ausdrücklich unbestätigt; übernommen
        werden sie erst mit Set-CpeMapping. Benötigt den Dienst NVD.
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
        $query = ($record.Name -replace '\s*\((x64|x86|64-bit|32-bit|User)\)', '' -replace '\s+v?\d+(\.\d+)+.*$', '').Trim()
        if (-not $query) { return }
        try {
            $r = Invoke-ServiceRequest -Service NVD -Setting $setting -CacheKey "cpes/keyword/$query" -MaxAge ([timespan]::FromDays(7)) `
                -Uri "$script:NvdBase/cpes/2.0?keywordSearch=$([uri]::EscapeDataString($query))&resultsPerPage=500"
        }
        catch {
            Write-Warning "CPE-Suche für '$query' nicht möglich: $($_.Exception.Message)"
            return
        }

        $publisherKey = Get-PublisherKey $record.Publisher
        $queryKey = ($query.ToLowerInvariant() -replace '[^a-z0-9]', '')
        $groups = @($r.products | ForEach-Object { $_.cpe.cpeName } | Where-Object { $_ -match '^cpe:2\.3:a:' } |
                ForEach-Object { (($_ -split '(?<!\\):')[0..4]) -join ':' } | Group-Object)
        $candidates = foreach ($g in $groups) {
            $parts = $g.Name -split '(?<!\\):'
            $vendor = $parts[3] -replace '\\', ''
            $product = $parts[4] -replace '\\', ''
            $productKey = ($product.ToLowerInvariant() -replace '[^a-z0-9]', '')
            # Grobe Bewertung: Produkt gleich/enthalten, Hersteller passt, viele Einträge = etabliert
            $score = 0
            if ($productKey -eq $queryKey) { $score += 3 } elseif ($productKey.Contains($queryKey) -or $queryKey.Contains($productKey)) { $score += 1 }
            if ($publisherKey -and $vendor.ToLowerInvariant().Contains($publisherKey)) { $score += 2 }
            [pscustomobject] @{
                PSTypeName = 'SoftwareInventory.CpeCandidate'
                Name       = $record.Name
                Cpe        = $g.Name
                Vendor     = $vendor
                Product    = $product
                Entries    = $g.Count
                Score      = $score
                Confirmed  = $false
                Record     = $record
            }
        }
        $candidates | Where-Object Score -gt 0 | Sort-Object @{ Expression = 'Score'; Descending = $true }, @{ Expression = 'Entries'; Descending = $true } |
            Select-Object -First $First
    }
}
