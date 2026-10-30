# CIRCL Vulnerability-Lookup als zweite Quelle für Sicherheitslücken. Abgefragt wird nur
# Hersteller und Produkt aus der CPE (keine Version); ausgewertet werden die CVE-Datensätze
# (Format CVE 5, Daten des CVE-Programms, CC BY 4.0) hier auf dem PC.
# Ergebnisse des Spikes: PR „CIRCL Vulnerability-Lookup as second vulnerability source“.

$script:CirclBase = 'https://vulnerability.circl.lu/api'
# Der Server begrenzt per_page stillschweigend auf 100 Zeilen (getestet am 30.10.2026 mit 500 und 1000).
# Nicht erhöhen: Beim Nachladen mit since endet das Blättern an der ersten Seite mit weniger Zeilen.
$script:CirclPageSize = 100
$script:CirclVersion = 'v?\d[\w.+-]*'
# Bestand je Produkt: nach so vielen Tagen wieder vollständig laden, dazwischen nur Änderungen (since).
$script:CirclFullDays = 30
# Schutz vor Endlosschleifen beim Blättern
$script:CirclMaxPages = 1000

function Get-CirclCve {
    <#
    .SYNOPSIS
        Alle CVE-Datensätze, die CIRCL zu Hersteller und Produkt einer CPE führt; Hashtabelle CVE-ID → Datensatz.
    .DESCRIPTION
        Je Produkt ein Bestand in cache\CIRCL\ (nur die ausgewerteten Felder). Jünger als CacheHours.CIRCL:
        ohne Anfrage. Älter: nur die seither geänderten Datensätze (since, nach dateUpdated), gleiche
        CVE-ID ersetzt den alten Datensatz. Vollständig neu geladen wird ohne lesbaren Bestand, nach
        30 Tagen ($script:CirclFullDays) und bei Neu prüfen (-Refresh). Geschrieben wird nur ein
        vollständiger Abruf oder ein vollständig gelungenes Nachladen; bricht es ab, bleibt der alte
        Bestand samt Datum stehen und wird als veraltet verwendet. Ein halber Bestand entsteht nie.
    #>
    param([Parameter(Mandatory)] [string[]] $CpeBase, $Setting)
    $all = @{}
    $maxAge = Get-CacheMaxAge -Service CIRCL -Setting $Setting
    foreach ($base in $CpeBase) {
        $parts = $base -split '(?<!\\):'
        $file = Get-CirclStoreFile -Vendor $parts[3] -Product $parts[4]
        $store = Read-CirclStore -Path $file
        $due = Test-Path -LiteralPath (Get-CirclDueFile $file)
        $refresh = Test-CacheRefresh $file   # vor dem Kurzschluss: merkt das Produkt für diesen Lauf
        $full = -not $store -or $refresh -or ([datetime]::UtcNow - $store.FullAt).TotalDays -gt $script:CirclFullDays
        if (-not $full -and -not $due -and ([datetime]::UtcNow - $store.FetchedAt) -le $maxAge) {
            Write-Verbose "CIRCL aus Zwischenspeicher: $($parts[3])/$($parts[4])"
            Add-CheckTrace -Service CIRCL -File $file -FetchedAt $store.FetchedAt -MaxAge $maxAge
            foreach ($id in $store.Records.Keys) { if (-not $all.ContainsKey($id)) { $all[$id] = $store.Records[$id] } }
            continue
        }
        $started = [datetime]::UtcNow
        try {
            if (-not $full) {
                $changes = Get-CirclPage -Vendor $parts[3] -Product $parts[4] -Since $store.FetchedAt -Setting $Setting
                # Blättern mit since unzuverlässig (Seite ohne neue Datensätze): lieber vollständig.
                if ($null -eq $changes) { $full = $true }
                else {
                    $records = $store.Records
                    foreach ($id in $changes.Keys) {
                        if ($changes[$id]) { $records[$id] = $changes[$id] } else { $records.Remove($id) }
                    }
                    $store = @{ FullAt = $store.FullAt; FetchedAt = $started; Records = $records }
                }
            }
            if ($full) {
                $records = @{}
                $loaded = Get-CirclPage -Vendor $parts[3] -Product $parts[4] -Setting $Setting
                foreach ($id in $loaded.Keys) { if ($loaded[$id]) { $records[$id] = $loaded[$id] } }
                $store = @{ FullAt = $started; FetchedAt = $started; Records = $records }
            }
        }
        catch {
            # Abbruch: alten (vollständigen) Bestand als veraltet nutzen, Datum nicht weitersetzen.
            if (-not $store) { throw }
            Write-Verbose "CIRCL nicht erreichbar, verwende Bestand vom $($store.FetchedAt.ToString('o'))"
            Add-CheckTrace -Service CIRCL -File $file -FetchedAt $store.FetchedAt -MaxAge $maxAge
            foreach ($id in $store.Records.Keys) { if (-not $all.ContainsKey($id)) { $all[$id] = $store.Records[$id] } }
            continue
        }
        Write-CirclStore -Path $file -Store $store
        Remove-Item -LiteralPath (Get-CirclDueFile $file) -Force -ErrorAction SilentlyContinue
        Add-CheckTrace -Service CIRCL -File $file -FetchedAt $store.FetchedAt -MaxAge $maxAge
        foreach ($id in $store.Records.Keys) { if (-not $all.ContainsKey($id)) { $all[$id] = $store.Records[$id] } }
    }
    $all
}

function Get-CirclPage {
    <#
    .SYNOPSIS
        Lädt alle Seiten der Suche zu einem Produkt; Hashtabelle CVE-ID → verschlankter Datensatz.
    .DESCRIPTION
        Zurückgezogene oder nicht veröffentlichte Datensätze stehen mit $null darin (aus dem Bestand
        entfernen). Mit -Since nur seit diesem Tag (UTC, einschließlich) geänderte Datensätze; diese
        Antwort hat kein total_count, geblättert wird bis zu einer nicht vollen Seite. Liefert eine
        volle Seite dabei keine neuen Datensätze, ist das Blättern unzuverlässig: Ergebnis $null.
    #>
    param([string] $Vendor, [string] $Product, [Nullable[datetime]] $Since, $Setting)
    $path = "$script:CirclBase/vulnerability/search/$([uri]::EscapeDataString($Vendor))/$([uri]::EscapeDataString($Product))"
    $sinceText = if ($null -ne $Since) { '&since=' + $Since.ToUniversalTime().ToString('yyyy-MM-dd', [cultureinfo]::InvariantCulture) }
    $all = @{}
    for ($page = 1; $page -le $script:CirclMaxPages; $page++) {
        $r = Invoke-ServiceRequest -Service CIRCL -Uri "$path`?per_page=$script:CirclPageSize&page=$page$sinceText" -Setting $Setting
        # Ohne since stehen die Quellen unter results, mit since direkt in der Antwort.
        $feeds = if ($r -and $r.PSObject.Properties['results']) { $r.results } else { $r }
        $rows = 0
        $new = 0
        if ($feeds) {
            foreach ($feed in $feeds.PSObject.Properties) {
                if ($feed.Value -isnot [array]) { continue }
                foreach ($row in @($feed.Value)) {
                    $rows++
                    $record = @($row)[-1]
                    if (-not $record -or -not $record.PSObject.Properties['cveMetadata']) { continue }
                    $id = ([string] $record.cveMetadata.cveId).ToUpperInvariant()
                    if (-not $id -or $all.ContainsKey($id)) { continue }
                    $new++
                    $state = [string] $record.cveMetadata.PSObject.Properties['state']?.Value
                    $all[$id] = if (-not $state -or $state -eq 'PUBLISHED') { ConvertTo-CirclStoreRecord $record }
                }
            }
        }
        if ($null -ne $Since) {
            if ($rows -lt $script:CirclPageSize) { return $all }
            if ($new -eq 0) { return $null }
        }
        else {
            # Nicht nach neuen IDs abbrechen: nvd- und cvelistv5-Zeile derselben CVE liegen oft auf verschiedenen Seiten.
            $total = if ($r -and $r.PSObject.Properties['total_count']) { [int] $r.total_count } else { 0 }
            if ($rows -eq 0 -or $page * $script:CirclPageSize -ge $total) { return $all }
        }
    }
    if ($null -ne $Since) { return $null }
    $all
}

function ConvertTo-CirclStoreRecord {
    # Nur die ausgewerteten Felder (Metadaten, affected, englische Beschreibung, CVSS), etwa 2 bis 30 % der Antwort.
    param($Record)
    $meta = $Record.cveMetadata
    $cna = $Record.containers.PSObject.Properties['cna']?.Value
    if ($null -eq $cna) { $cna = [pscustomobject] @{} }
    $description = @($cna.PSObject.Properties['descriptions']?.Value) | Where-Object { $_ -and $_.lang -like 'en*' } | Select-Object -First 1
    $slim = [ordered]@{
        cveMetadata = [ordered]@{
            cveId         = ([string] $meta.cveId).ToUpperInvariant()
            state         = $meta.PSObject.Properties['state']?.Value
            datePublished = $meta.PSObject.Properties['datePublished']?.Value
            dateUpdated   = $meta.PSObject.Properties['dateUpdated']?.Value
        }
        containers  = [ordered]@{
            cna = [ordered]@{
                affected     = @($cna.PSObject.Properties['affected']?.Value | Where-Object { $_ })
                descriptions = @($description | Where-Object { $_ } | ForEach-Object { [ordered]@{ lang = $_.lang; value = $_.value } })
                metrics      = @($cna.PSObject.Properties['metrics']?.Value | Where-Object { $_ })
            }
            adp = @(@($Record.containers.PSObject.Properties['adp']?.Value) | Where-Object { $_ } | ForEach-Object {
                    [ordered]@{ affected = @($_.PSObject.Properties['affected']?.Value | Where-Object { $_ }); metrics = @($_.PSObject.Properties['metrics']?.Value | Where-Object { $_ }) }
                })
        }
    }
    # Gleiche Form wie aus dem Bestand gelesen
    $slim | ConvertTo-Json -Depth 30 -Compress | ConvertFrom-Json -DateKind String
}

function Get-CirclStoreFile {
    param([string] $Vendor, [string] $Product)
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes("store/$Vendor/$Product")))
    Join-Path (Join-Path (Get-CacheDirectory) 'CIRCL') "store-$hash.json"
}

function Get-CirclDueFile {
    # Merker „beim nächsten Mal nachladen“ (Clear-CheckCache), neben dem Bestand.
    param([string] $StoreFile)
    [System.IO.Path]::ChangeExtension($StoreFile, '.due')
}

function Read-CirclStore {
    # Bestand mit FullAt, FetchedAt (UTC) und Records; $null, wenn er fehlt, unlesbar oder unvollständig ist.
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
        $parse = { param($s) [datetime]::Parse($s, [cultureinfo]::InvariantCulture, 'RoundtripKind').ToUniversalTime() }
        if (-not $data.PSObject.Properties['Records'] -or -not $data.FullAt -or -not $data.FetchedAt) { throw 'unvollständig' }
        $records = @{}
        foreach ($record in @($data.Records)) {
            if ($record) { $records[([string] $record.cveMetadata.cveId).ToUpperInvariant()] = $record }
        }
        @{ FullAt = & $parse $data.FullAt; FetchedAt = & $parse $data.FetchedAt; Records = $records }
    }
    catch {
        Write-Verbose "CIRCL-Bestand unlesbar, wird vollständig neu geladen: $Path"
        $null
    }
}

function Write-CirclStore {
    # Erst in eine Datei daneben schreiben, dann ersetzen: Bestand und Datum ändern sich nur gemeinsam.
    param([string] $Path, [hashtable] $Store)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    $temp = "$Path.part"
    [pscustomobject] [ordered]@{
        FullAt    = $Store.FullAt.ToString('o')
        FetchedAt = $Store.FetchedAt.ToString('o')
        Records   = @($Store.Records.Keys | Sort-Object | ForEach-Object { $Store.Records[$_] })
    } | ConvertTo-Json -Depth 32 -Compress | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    [System.IO.File]::Move($temp, $Path, $true)
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
