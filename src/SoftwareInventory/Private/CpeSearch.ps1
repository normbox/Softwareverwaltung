# Suchbegriffe und Bewertung für CPE-Vorschläge (Find-CpeCandidate).
# Vorschläge bleiben unbestätigt; übernommen wird nur, was der Benutzer bestätigt (Set-CpeMapping).

$script:CpeVendorAliasPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Data\cpe-vendor-alias.json'
$script:CpeVendorAlias = $null

# Wörter, die nur Ausgabe, Architektur oder Kanal beschreiben und die Suche verfälschen
$script:CpeSearchNoise = @('x64', 'x86', 'arm64', '64-bit', '32-bit', '64bit', '32bit', 'release', 'stable', 'setup', 'installer', 'user')

function Get-CpeVendorAlias {
    # Herstellerschlüssel (wie Get-PublisherKey) -> NVD-Herstellernamen, z. B. "irfan" -> "irfanview".
    if ($null -eq $script:CpeVendorAlias) {
        $script:CpeVendorAlias = @{}
        try {
            $data = Get-Content -LiteralPath $script:CpeVendorAliasPath -Raw | ConvertFrom-Json
            foreach ($p in $data.Vendors.PSObject.Properties) { $script:CpeVendorAlias[$p.Name] = [string[]] @($p.Value) }
        }
        catch { Write-Verbose "Herstelleraliase nicht lesbar: $($_.Exception.Message)" }
    }
    $script:CpeVendorAlias
}

function ConvertTo-CpeSearchName {
    <#
    .SYNOPSIS
        Programmname ohne Version, Architektur, Sprache und Zusätze in Klammern.
    .EXAMPLE
        ConvertTo-CpeSearchName 'Wireshark 4.6.6 x64'   # Wireshark
        ConvertTo-CpeSearchName 'PuTTY release 0.85 (64-bit)'   # PuTTY
    #>
    param([string] $Name)
    if (-not $Name) { return $null }
    $text = $Name -replace '\([^)]*\)', ' '                       # (x64), (User), (Remove or Repair)
    $text = $text -replace '\s+-\s+v?\d+(\.\d+)+.*$', ''           # "… - 12.0.30501"
    $text = $text -replace '\s+v?\d+(\.\d+)+.*$', ''               # "… 4.6.6 x64"
    $words = $text -split '\s+' | Where-Object { $_ -and $script:CpeSearchNoise -notcontains $_.ToLowerInvariant() }
    $result = ($words -join ' ').Trim(' ', '-', ',')
    if ($result) { $result }
}

function ConvertFrom-WingetIdToSearchName {
    # Produktteil einer winget-ID: "Ghisler.TotalCommander" -> "Total Commander". Store-IDs ohne Punkt liefern nichts.
    param([string] $WingetId)
    if (-not $WingetId -or $WingetId -notmatch '\.') { return $null }
    $segment = ($WingetId -split '\.')[1]
    if (-not $segment -or $segment -match '^\d+$') { return $null }
    ($segment -creplace '(?<=[a-z])(?=[A-Z])', ' ').Trim()
}

function Get-CpeSearchQuery {
    <#
    .SYNOPSIS
        Suchbegriffe für das CPE-Wörterbuch der NVD in sinnvoller Reihenfolge, ohne Doppelte.
    .DESCRIPTION
        1. bereinigter Programmname, 2. Produktteil der winget-ID. Doppelte (ohne Groß-/Kleinschreibung
        und Leerzeichen) entfallen, damit keine Abfrage doppelt an die NVD geht.
    #>
    param([Parameter(Mandatory)] $Record)
    $seen = @{}
    foreach ($query in @((ConvertTo-CpeSearchName $Record.Name), (ConvertFrom-WingetIdToSearchName $Record.WingetId))) {
        if (-not $query -or $query.Length -lt 2) { continue }
        $key = ConvertTo-CpeCompareKey $query
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $query
    }
}

function ConvertTo-CpeCompareKey {
    # Nur Buchstaben und Ziffern, klein: "Node.js" -> "nodejs", "visual_c\+\+" -> "visualc"
    param([string] $Text)
    ($Text.ToLowerInvariant() -replace '\\', '' -replace '[^\p{L}\p{N}]', '')
}

function Get-CpeCandidateScore {
    <#
    .SYNOPSIS
        Grobe Bewertung eines CPE-Produkts für ein Programm (0 = passt nicht).
    .DESCRIPTION
        Produkt gleich einem Suchbegriff: +3, darin enthalten oder umgekehrt: +1.
        Hersteller passt zum Herausgeber (erstes Wort oder Alias): +2.
        Ohne Bezug zum Produkt 0, sonst schlüge „Microsoft“ jedes Microsoft-Produkt vor.
    #>
    param([string] $Vendor, [string] $Product, [string[]] $Query, [string] $Publisher)
    $productKey = ConvertTo-CpeCompareKey $Product
    $vendorKey = ConvertTo-CpeCompareKey $Vendor
    $queryKeys = @($Query | ForEach-Object { ConvertTo-CpeCompareKey $_ } | Where-Object { $_ })
    if ($queryKeys -contains $productKey) { $score = 3 }
    elseif ($productKey -and ($queryKeys | Where-Object { $productKey.Contains($_) -or $_.Contains($productKey) })) { $score = 1 }
    else { return 0 }

    $publisherKey = Get-PublisherKey $Publisher
    if ($publisherKey) {
        $vendors = @(Get-PublisherWord $Publisher) + @((Get-CpeVendorAlias)[$publisherKey])
        if ($vendors | Where-Object { $_ -and $vendorKey.Contains((ConvertTo-CpeCompareKey $_)) }) { $score += 2 }
    }
    $score
}

$script:PublisherStopWords = @('the', 'inc', 'llc', 'ltd', 'gmbh', 'corporation', 'corp', 'company', 'software', 'team', 'foundation',
    'project', 'community', 'developer', 'developers', 'international', 'limited', 'srl', 'and', 'network', 'electronics', 'industries', 'https', 'www', 'org', 'com')

function Get-PublisherWord {
    # Aussagekräftige Wörter des Herausgebers: "The Document Foundation" -> document; "The GIMP Team" -> gimp
    param([string] $Publisher)
    ($Publisher.ToLowerInvariant() -replace '[^\p{L}\p{N} ]', ' ') -split '\s+' |
        Where-Object { $_.Length -ge 3 -and $script:PublisherStopWords -notcontains $_ } | Select-Object -Unique
}
