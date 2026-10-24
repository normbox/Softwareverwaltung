# Katalog: kleine JSON-Dateien je Produkt (Catalog\*.json) mit Zuordnung und Versionsquellen.
# Aufbau und Regeln für neue Einträge: docs/KATALOG.md

$script:CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Catalog'
$script:CatalogCache = $null

function Get-SoftwareCatalog {
    <#
    .SYNOPSIS
        Lädt alle Katalogeinträge; fehlerhafte Dateien werden mit Warnung übersprungen.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param([string] $Path = $script:CatalogPath, [switch] $Force)

    if ($script:CatalogCache -and -not $Force -and $Path -eq $script:CatalogPath) { return $script:CatalogCache }
    $entries = foreach ($file in Get-ChildItem -LiteralPath $Path -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
        try {
            $entry = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $problems = @(Test-CatalogEntry -Entry $entry -FileName $file.BaseName)
            if ($problems) { throw ($problems -join '; ') }
            $entry
        }
        catch {
            Write-Warning "Katalogeintrag $($file.Name) übersprungen: $_"
        }
    }
    $entries = @($entries)
    if ($Path -eq $script:CatalogPath) { $script:CatalogCache = $entries }
    $entries
}

function Test-CatalogEntry {
    # Liefert eine Liste von Problemen; leer = gültig.
    param($Entry, [string] $FileName)
    $has = { param($o, $n) [bool] ($o -and $o.PSObject.Properties[$n] -and $o.$n) }

    if (-not (& $has $Entry 'Id')) { 'Id fehlt'; return }
    if ($FileName -and $Entry.Id -ne $FileName) { "Id '$($Entry.Id)' passt nicht zum Dateinamen '$FileName'" }
    if ($Entry.Id -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { "Id '$($Entry.Id)' muss aus Kleinbuchstaben, Ziffern und Bindestrichen bestehen" }
    if (-not (& $has $Entry 'Name')) { 'Name fehlt' }
    if (-not (& $has $Entry 'Match')) { 'Match fehlt'; return }

    $m = $Entry.Match
    $strong = (& $has $m 'WingetId') -or (& $has $m 'PackageFamilyName')
    if (-not $strong -and -not (& $has $m 'NamePattern')) { 'Match braucht WingetId, PackageFamilyName oder NamePattern' }
    if ((& $has $m 'NamePattern') -and -not (& $has $m 'Publisher')) { 'NamePattern braucht Publisher (ein Name allein reicht nicht)' }
    $patterns = @(Get-CatalogValue $m 'NamePattern')
    if (& $has $Entry 'GitHub') { $patterns += @(Get-CatalogValue $Entry.GitHub 'TagPattern') }
    foreach ($pattern in $patterns) {
        if (-not $pattern) { continue }
        try { [void] [regex]::new($pattern) } catch { "Ungültiges Muster '$pattern'" }
    }
    if (& $has $m 'Publisher') {
        foreach ($p in $m.Publisher) { if (-not (Get-PublisherKey $p)) { "Hersteller '$p' ergibt keinen Vergleichsschlüssel (mindestens 3 Zeichen im ersten Wort)" } }
    }
    if (& $has $Entry 'GitHub') {
        if ($Entry.GitHub.Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { "GitHub.Repository '$($Entry.GitHub.Repository)' muss die Form owner/repo haben" }
        $tag = Get-CatalogValue $Entry.GitHub 'TagPattern'
        if ($tag -and $tag -notmatch '\(\?<version>') { 'GitHub.TagPattern braucht eine Gruppe (?<version>...)' }
    }
    # CPE ohne Version: cpe:2.3:a:<hersteller>:<produkt> (Sonderzeichen mit \ maskiert, z. B. notepad\+\+)
    foreach ($cpe in @(Get-CatalogValue $Entry 'Cpe')) {
        if (-not $cpe) { continue }
        if ($cpe -notmatch '^cpe:2\.3:[aho]:(\\.|[^:\\])+:(\\.|[^:\\])+$') { "Cpe '$cpe' muss die Form cpe:2.3:a:hersteller:produkt haben (ohne Version)" }
    }
    foreach ($kev in @(Get-CatalogValue $Entry 'Kev')) {
        if (-not $kev) { continue }
        if (-not (& $has $kev 'Vendor')) { 'Kev.Vendor fehlt' }
        $productPattern = Get-CatalogValue $kev 'ProductPattern'
        if (-not $productPattern) { 'Kev.ProductPattern fehlt'; continue }
        try { [void] [regex]::new($productPattern) } catch { "Ungültiges Muster '$productPattern'" }
    }
}

function Find-CatalogEntry {
    <#
    .SYNOPSIS
        Sucht den Katalogeintrag zu einem Datensatz.
    .DESCRIPTION
        Reihenfolge: winget-ID, PackageFamilyName, dann Name-Muster zusammen mit Hersteller.
        Ein Name allein ordnet nie zu. Liefert den Eintrag mit MatchedBy oder $null.
    #>
    param([Parameter(Mandatory)] $Record, [object[]] $Catalog = (Get-SoftwareCatalog))

    foreach ($entry in $Catalog) {
        $m = $entry.Match
        if ($Record.WingetId -and @(Get-CatalogValue $m 'WingetId') -contains $Record.WingetId) {
            return [pscustomobject] @{ Entry = $entry; MatchedBy = 'WingetId' }
        }
        if ($Record.PackageFamilyName -and @(Get-CatalogValue $m 'PackageFamilyName') -contains $Record.PackageFamilyName) {
            return [pscustomobject] @{ Entry = $entry; MatchedBy = 'PackageFamilyName' }
        }
    }
    foreach ($entry in $Catalog) {
        $m = $entry.Match
        $pattern = Get-CatalogValue $m 'NamePattern'
        if (-not $pattern -or $Record.Name -notmatch $pattern) { continue }
        $allowed = @($m.Publisher | ForEach-Object { Get-PublisherKey $_ })
        $candidates = @($Record.Publisher, (Get-CatalogValue $Record 'Signer')) | ForEach-Object { Get-PublisherKey $_ } | Where-Object { $_ }
        if ($candidates | Where-Object { $_ -in $allowed }) {
            return [pscustomobject] @{ Entry = $entry; MatchedBy = 'NameAndPublisher' }
        }
    }
    $null
}

function Get-CatalogValue {
    # Wert einer optionalen Eigenschaft oder $null (StrictMode-sicher).
    param($Object, [string] $Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { $property.Value }
}
