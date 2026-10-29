# CIRCL Vulnerability-Lookup als zweite Quelle für Sicherheitslücken. Abgefragt wird nur
# Hersteller und Produkt aus der CPE (keine Version); ausgewertet werden die CVE-Datensätze
# (Format CVE 5, Daten des CVE-Programms, CC BY 4.0) hier auf dem PC.
# Ergebnisse des Spikes: PR „CIRCL Vulnerability-Lookup as second vulnerability source“.

$script:CirclBase = 'https://vulnerability.circl.lu/api'
$script:CirclPageSize = 100
$script:CirclVersion = 'v?\d[\w.+-]*'

function Get-CirclCve {
    <#
    .SYNOPSIS
        Alle CVE-Datensätze, die CIRCL zu Hersteller und Produkt einer CPE führt; Hashtabelle CVE-ID → Datensatz.
    .DESCRIPTION
        Seitenweise über /vulnerability/search/{vendor}/{product}. Die Antwort enthält dieselben
        Datensätze unter mehreren Quellen (nvd, cvelistv5); sie werden nach CVE-ID zusammengefasst.
    #>
    param([Parameter(Mandatory)] [string[]] $CpeBase, $Setting)
    $all = @{}
    foreach ($base in $CpeBase) {
        $parts = $base -split '(?<!\\):'
        $vendor = [uri]::EscapeDataString($parts[3])
        $product = [uri]::EscapeDataString($parts[4])
        $page = 1
        do {
            $uri = "$script:CirclBase/vulnerability/search/$vendor/$product`?per_page=$script:CirclPageSize&page=$page"
            $r = Invoke-ServiceRequest -Service CIRCL -Uri $uri -CacheKey "search/$($parts[3])/$($parts[4])/$page" -Setting $Setting
            $count = 0
            $results = if ($r -and $r.PSObject.Properties['results']) { $r.results }
            if ($results) {
                foreach ($feed in $results.PSObject.Properties) {
                    foreach ($row in @($feed.Value)) {
                        $record = @($row)[-1]
                        if (-not $record -or -not $record.PSObject.Properties['cveMetadata']) { continue }
                        $count++
                        $id = ([string] $record.cveMetadata.cveId).ToUpperInvariant()
                        if ($id -and -not $all.ContainsKey($id)) { $all[$id] = $record }
                    }
                }
            }
            $total = if ($r -and $r.PSObject.Properties['total_count']) { [int] $r.total_count } else { 0 }
            $page++
        } while ($count -gt 0 -and ($page - 1) * $script:CirclPageSize -lt $total)
    }
    $all
}

function ConvertFrom-CveVersionText {
    <#
    .SYNOPSIS
        Liest eine Versionsangabe aus dem Feld „version“ eines CVE-5-Datensatzes.
    .DESCRIPTION
        Einfache Formen: „< 8.9.6.1“, „<= 26.00“, „>= 9.11, < 26.01“. Feste englische Freitextmuster:
        „Fixed in X“, „before X“, „prior to X“ (jeweils < X) und „X and earlier“ (<= X).
        Eine reine Versionsnummer liefert Exact. Alles andere: $null (nicht auswertbar).
    #>
    param([string] $Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $t = $Text.Trim()
    $v = $script:CirclVersion
    $clean = { param($s) ($s -replace '^[vV]', '') -replace '[.\-]+$', '' }
    if ($t -match "^(?:(?<lo>>=?)\s*(?<a>$v)\s*(?:,|and)?\s*)?(?<hi><=?)\s*(?<b>$v)$") {
        return [pscustomobject] @{
            Start = if ($Matches['a']) { & $clean $Matches['a'] }; StartIncluding = $Matches['lo'] -eq '>='
            End = & $clean $Matches['b']; EndIncluding = $Matches['hi'] -eq '<='; Exact = $null
        }
    }
    if ($t -match "^(?<lo>>=?)\s*(?<a>$v)$") {
        return [pscustomobject] @{ Start = & $clean $Matches['a']; StartIncluding = $Matches['lo'] -eq '>='; End = $null; EndIncluding = $false; Exact = $null }
    }
    foreach ($pattern in "(?i)\bfixed in\s+(?:version\s+)?(?<b>$v)", "(?i)\bbefore\s+(?:version\s+)?(?<b>$v)", "(?i)\bprior to\s+(?:version\s+)?(?<b>$v)") {
        if ($t -match $pattern) {
            return [pscustomobject] @{ Start = $null; StartIncluding = $false; End = & $clean $Matches['b']; EndIncluding = $false; Exact = $null }
        }
    }
    if ($t -match "(?i)(?<b>$v)\s+and\s+earlier\b") {
        return [pscustomobject] @{ Start = $null; StartIncluding = $false; End = & $clean $Matches['b']; EndIncluding = $true; Exact = $null }
    }
    if ($t -match "^$v$" -and $t -ne '0') {
        return [pscustomobject] @{ Start = $null; StartIncluding = $false; End = $null; EndIncluding = $false; Exact = & $clean $t }
    }
    $null
}

function ConvertFrom-CveVersionEntry {
    # Bereich aus einem Eintrag affected[].versions[] (status = affected); $null, wenn nicht auswertbar.
    param($Entry)
    if ($Entry.PSObject.Properties['status']?.Value -ne 'affected') { return $null }
    $type = $Entry.PSObject.Properties['versionType']?.Value
    if ($type -and $type -notin 'semver', 'custom', 'string', 'maven', 'python', 'rpm') { return $null }   # z. B. git-Commits
    $version = [string] $Entry.PSObject.Properties['version']?.Value
    $lessThan = [string] $Entry.PSObject.Properties['lessThan']?.Value
    $lessOrEqual = [string] $Entry.PSObject.Properties['lessThanOrEqual']?.Value
    if ($lessThan -or $lessOrEqual) {
        $start = if ($version -and $version -notin '0', '*', 'n/a', 'unspecified') { $version }
        $end = if ($lessOrEqual) { $lessOrEqual } else { $lessThan }
        if ($end -eq '*') { $end = $null }
        if (-not $start -and -not $end) { return $null }
        return [pscustomobject] @{ Start = $start; StartIncluding = $true; End = $end; EndIncluding = [bool] $lessOrEqual; Exact = $null }
    }
    ConvertFrom-CveVersionText $version
}

function Format-VersionRange {
    # Bereich als kurzer Text: „>= 9.11, < 26.01“, „< 26.03“ oder „= 26.01“.
    param($Range)
    if ($Range.Exact) { return "= $($Range.Exact)" }
    $parts = @()
    if ($Range.Start) { $parts += "$(if ($Range.StartIncluding) { '>=' } else { '>' }) $($Range.Start)" }
    if ($Range.End) { $parts += "$(if ($Range.EndIncluding) { '<=' } else { '<' }) $($Range.End)" }
    $parts -join ', '
}

function Test-VersionInRange {
    # $true/$false; $null, wenn eine Grenze nicht vergleichbar ist.
    param([string] $Version, $Range)
    if ($Range.Exact) {
        $cmp = Compare-SoftwareVersion $Version $Range.Exact
        if ($null -eq $cmp) { return $null }
        return $cmp -eq 0
    }
    if ($Range.Start) {
        $cmp = Compare-SoftwareVersion $Version $Range.Start
        if ($null -eq $cmp) { return $null }
        if ($cmp -lt 0 -or ($cmp -eq 0 -and -not $Range.StartIncluding)) { return $false }
    }
    if ($Range.End) {
        $cmp = Compare-SoftwareVersion $Version $Range.End
        if ($null -eq $cmp) { return $null }
        if ($cmp -gt 0 -or ($cmp -eq 0 -and -not $Range.EndIncluding)) { return $false }
    }
    $true
}

function Get-CveProductKey {
    # Vergleichsschlüssel für Hersteller/Produkt: klein, nur Buchstaben und Ziffern („notepad\+\+“ → notepad).
    param([string] $Text)
    ($Text -replace '\\', '').ToLowerInvariant() -replace '[^\p{L}\p{N}]', ''
}

function Get-CirclAffectedBlock {
    <#
    .SYNOPSIS
        Einträge affected[] aus CNA und ADP (CISA), die zum Produkt gehören.
    .DESCRIPTION
        Passt, wenn eine CPE des Eintrags mit der CPE beginnt oder der Produktname übereinstimmt
        (gleich, oder enthalten bei passendem Hersteller). Einträge „n/a“ zählen nur, wenn kein
        Eintrag passt. Passt nichts, ist die CVE für dieses Produkt nicht auswertbar.
    #>
    param($Record, [string[]] $CpeBase)
    $blocks = @($Record.containers.cna.PSObject.Properties['affected']?.Value) +
        @(@($Record.containers.PSObject.Properties['adp']?.Value) | Where-Object { $_ } | ForEach-Object { @($_.PSObject.Properties['affected']?.Value) }) |
        Where-Object { $_ }
    $named = foreach ($block in $blocks) {
        $cpes = @($block.PSObject.Properties['cpes']?.Value) | Where-Object { $_ }
        $product = Get-CveProductKey ([string] $block.PSObject.Properties['product']?.Value)
        $vendor = Get-CveProductKey ([string] $block.PSObject.Properties['vendor']?.Value)
        foreach ($base in $CpeBase) {
            $parts = $base -split '(?<!\\):'
            $cpeVendor = Get-CveProductKey $parts[3]
            $cpeProduct = Get-CveProductKey $parts[4]
            $byCpe = $cpes | Where-Object { ([string] $_).StartsWith("${base}:", [StringComparison]::OrdinalIgnoreCase) }
            $sameVendor = $vendor -and ($vendor.Contains($cpeVendor) -or $cpeVendor.Contains($vendor))
            $byName = $product -and ($product -eq $cpeProduct -or ($sameVendor -and ($product.Contains($cpeProduct) -or $cpeProduct.Contains($product))))
            if ($byCpe -or $byName) { $block; break }
        }
    }
    if ($named) { return @($named) }
    @($blocks | Where-Object { (Get-CveProductKey ([string] $_.PSObject.Properties['product']?.Value)) -in '', 'na' })
}

function Get-CirclAssessment {
    <#
    .SYNOPSIS
        Ist die Version laut CVE-Datensatz von CIRCL betroffen?
    .OUTPUTS
        Verdict: Affected, NotAffected oder NotEvaluable; Range: ausgewertete Bereiche als Text.
    .DESCRIPTION
        Werden nur einzelne Versionen genannt (oft nur die getestete), gilt: gleiche Version
        betroffen, neuere nicht betroffen, ältere nicht auswertbar (lieber ein Fehlalarm mehr).
    #>
    param($Record, [string[]] $CpeBase, [string] $Version)
    $ranges = @(foreach ($block in Get-CirclAffectedBlock -Record $Record -CpeBase $CpeBase) {
            foreach ($entry in @($block.PSObject.Properties['versions']?.Value)) { if ($entry) { ConvertFrom-CveVersionEntry $entry } }
        }) | Where-Object { $_ }
    $text = (@($ranges | ForEach-Object { Format-VersionRange $_ }) | Select-Object -Unique) -join '; '
    if (-not $ranges) { return [pscustomobject] @{ Verdict = 'NotEvaluable'; Range = $null } }
    $results = @(foreach ($range in $ranges) { Test-VersionInRange -Version $Version -Range $range })
    if ($results -contains $true) { return [pscustomobject] @{ Verdict = 'Affected'; Range = $text } }
    if ($null -in $results) { return [pscustomobject] @{ Verdict = 'NotEvaluable'; Range = $text } }
    $exact = @($ranges | Where-Object Exact)
    if ($exact.Count -eq $ranges.Count) {
        $older = $exact | Where-Object { (Compare-SoftwareVersion $Version $_.Exact) -lt 0 }
        if ($older) { return [pscustomobject] @{ Verdict = 'NotEvaluable'; Range = $text } }
    }
    [pscustomobject] @{ Verdict = 'NotAffected'; Range = $text }
}

function Get-Cve5Info {
    # Beschreibung, Veröffentlichung und CVSS aus einem CVE-5-Datensatz (CNA vor ADP, neueste CVSS-Version zuerst).
    param($Record, [int] $MaxLength = 400)
    $cna = $Record.containers.cna
    $text = @($cna.PSObject.Properties['descriptions']?.Value) | Where-Object { $_ -and $_.lang -like 'en*' } | Select-Object -First 1 | ForEach-Object value
    if ($text) {
        $text = $text.Trim()
        if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength - 1) + '…' }
    }
    $metrics = @($cna.PSObject.Properties['metrics']?.Value) +
        @(@($Record.containers.PSObject.Properties['adp']?.Value) | Where-Object { $_ } | ForEach-Object { @($_.PSObject.Properties['metrics']?.Value) }) |
        Where-Object { $_ }
    $cvss = $null
    foreach ($key in 'cvssV4_0', 'cvssV3_1', 'cvssV3_0', 'cvssV2_0') {
        $data = $metrics | ForEach-Object { $_.PSObject.Properties[$key]?.Value } | Where-Object { $_ } | Select-Object -First 1
        if ($data) { $cvss = [pscustomobject] @{ Score = [double] $data.baseScore; Severity = $data.PSObject.Properties['baseSeverity']?.Value; Version = $data.version }; break }
    }
    [pscustomobject] @{
        Published   = $Record.cveMetadata.PSObject.Properties['datePublished']?.Value
        Description = $text
        Cvss        = $cvss
    }
}
