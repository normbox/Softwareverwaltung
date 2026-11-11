# Versionen normalisieren und vergleichen. Nicht lesbare Versionen ergeben „unbekannt“ ($null),
# nie „gleich“ – sonst würde ein ungeprüftes Programm als aktuell gelten.

# Rangfolge der Vorabversionen (kleiner = früher).
$script:PrereleaseRank = @{ dev = 0; nightly = 0; snapshot = 0; alpha = 1; a = 1; beta = 2; b = 2; pre = 3; preview = 3; rc = 4 }

function ConvertTo-NormalizedVersion {
    <#
    .SYNOPSIS
        Zerlegt eine Versionsangabe in Zahlenteile und Zusatz.
    .DESCRIPTION
        Entfernt Präfixe (v, Version) und Zusätze wie „(x64)“, „+build“ oder Commit-Hashes.
        Gibt $null zurück, wenn keine Versionsnummer erkennbar ist oder die Angabe ein
        Bereich ist (winget meldet z. B. „< 2026.3.1“).
    .EXAMPLE
        ConvertTo-NormalizedVersion 'v24.08-beta2'   # Parts 24,8; Prerelease beta, 2
    #>
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $text = $Version.Trim()
    if ($text -match '^[<>]') { return $null }
    $text = $text -replace '^(?i)(version\s*|v(?=\d))', ''

    if ($text -notmatch '^(?<num>\d+(?:\.\d+)*)(?<rest>.*)$') { return $null }
    $parts = [long[]] @($Matches.num -split '\.' | ForEach-Object { [long] $_ })
    $rest = $Matches.rest

    $prerelease = $null
    $prereleaseNumber = 0
    $letter = $null
    # Build-Metadaten und Klammerzusätze haben keine Bedeutung für die Reihenfolge.
    $label = ($rest -replace '\+.*$', '' -replace '\s*\(.*$', '').Trim()
    if ($label -match '^[-._ ]?(?<kind>dev|nightly|snapshot|alpha|beta|preview|pre|rc|a|b)[-._ ]?(?<n>\d*)$') {
        $prerelease = $Matches.kind.ToLowerInvariant()
        if ($Matches.n) { $prereleaseNumber = [long] $Matches.n }
    }
    elseif ($label -cmatch '^(?<letter>[a-z])$') {
        # Patch-Buchstabe direkt an der Zahl (OpenSSL 1.1.1w): zählt als höher
        $letter = $Matches.letter
    }
    elseif ($label -and $label -notmatch '^[-._ ]?(g?[0-9a-f]{7,40})$') {
        # Unbekannter Rest (z. B. „7-Zip 26.05“ ergäbe sonst Version 7): lieber unbekannt als falsch.
        # Ein Commit-Hash als Zusatz wird dagegen ignoriert.
        return $null
    }

    # Nachgestellte Nullen zählen nicht: 24.8 = 24.8.0.0
    $significant = [System.Collections.Generic.List[long]]::new($parts)
    while ($significant.Count -gt 1 -and $significant[$significant.Count - 1] -eq 0) { $significant.RemoveAt($significant.Count - 1) }

    [pscustomobject] @{
        PSTypeName       = 'SoftwareInventory.Version'
        Raw              = $Version
        Parts            = [long[]] $significant
        Normalized       = ($significant -join '.') + $(if ($letter) { $letter }) + $(if ($prerelease) { "-$prerelease" + $(if ($prereleaseNumber) { $prereleaseNumber }) })
        Prerelease       = $prerelease
        PrereleaseNumber = $prereleaseNumber
        Letter           = $letter
    }
}

function Compare-NormalizedVersion {
    # -1, 0 oder 1; beide Eingaben müssen normalisiert sein.
    param([Parameter(Mandatory)] $Reference, [Parameter(Mandatory)] $Difference)

    $max = [Math]::Max($Reference.Parts.Count, $Difference.Parts.Count)
    for ($i = 0; $i -lt $max; $i++) {
        $a = if ($i -lt $Reference.Parts.Count) { $Reference.Parts[$i] } else { 0 }
        $b = if ($i -lt $Difference.Parts.Count) { $Difference.Parts[$i] } else { 0 }
        if ($a -ne $b) { return [Math]::Sign($a - $b) }
    }

    # Gleiche Zahlen: Vorabversion < Release < Release mit Patch-Buchstabe
    $rank = { param($v) if ($v.Prerelease) { -1 } elseif ($v.Letter) { 1 } else { 0 } }
    $ra = & $rank $Reference
    $rb = & $rank $Difference
    if ($ra -ne $rb) { return [Math]::Sign($ra - $rb) }
    if ($Reference.Letter -and $Reference.Letter -ne $Difference.Letter) {
        return [Math]::Sign([string]::CompareOrdinal($Reference.Letter, $Difference.Letter))
    }
    if ($Reference.Prerelease) {
        $pa = $script:PrereleaseRank[$Reference.Prerelease]
        $pb = $script:PrereleaseRank[$Difference.Prerelease]
        if ($pa -ne $pb) { return [Math]::Sign($pa - $pb) }
        return [Math]::Sign($Reference.PrereleaseNumber - $Difference.PrereleaseNumber)
    }
    0
}

function Get-VersionDate {
    <#
    .SYNOPSIS
        Datum, wenn eine normalisierte Version wie ein Datum aussieht (yt-dlp 2025.01.15); sonst $null.
    .DESCRIPTION
        Verlangt drei Teile, Jahr ab 1900, Monat 1–12 und einen gültigen Tag. Build-Nummern wie 2302.1.0
        (Tag 0), 1903 (kein Monat) oder 2025.2.0.33046 (Foxit, Tag 0) sind kein Datum.
    #>
    param($Normalized)
    if (-not $Normalized -or $Normalized.Parts.Count -lt 3) { return $null }
    $year, $month, $day = $Normalized.Parts[0..2]
    if ($year -lt 1900 -or $year -gt 9999 -or $month -lt 1 -or $month -gt 12 -or $day -lt 1 -or $day -gt [datetime]::DaysInMonth($year, $month)) { return $null }
    [datetime]::new($year, $month, $day)
}

function ConvertFrom-DateBound {
    <#
    .SYNOPSIS
        Datum, wenn eine Versionsgrenze ein Datum ist; sonst $null.
    .DESCRIPTION
        JJJJ-MM-TT und JJJJMMTT sind immer ein Datum (wenn gültig). JJJJ.MM.TT nur, wenn die installierte
        Version normal ist (Hauptversion unter 1900); sonst ist es eine Versionsnummer wie bei yt-dlp oder Foxit.
    #>
    param([string] $Bound, [bool] $InstalledIsNormal)
    $b = $Bound.Trim()
    $m = [regex]::Match($b, '^(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})$')
    if (-not $m.Success) { $m = [regex]::Match($b, '^(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})$') }
    if (-not $m.Success -and $InstalledIsNormal) { $m = [regex]::Match($b, '^(?<y>\d{4})\.(?<m>\d{1,2})\.(?<d>\d{1,2})$') }
    if (-not $m.Success) { return $null }
    $year = [int] $m.Groups['y'].Value; $month = [int] $m.Groups['m'].Value; $day = [int] $m.Groups['d'].Value
    if ($year -lt 1900 -or $month -lt 1 -or $month -gt 12 -or $day -lt 1 -or $day -gt [datetime]::DaysInMonth($year, $month)) { return $null }
    [datetime]::new($year, $month, $day)
}

function Compare-VersionBound {
    <#
    .SYNOPSIS
        Vergleicht die installierte Version mit einer Versionsgrenze aus NVD oder CVE-Datensatz.
    .DESCRIPTION
        Ergebnis -1, 0 oder 1; $null, wenn die Grenze nicht vergleichbar ist. Nicht vergleichbar sind:
        Commit-Kennungen, Datumsgrenzen gegenüber normalen Versionen (FFmpeg 9.0.2 gegen 2025-01-13),
        unlesbare Angaben. Eine Datumsgrenze ist nur mit einer datumsartigen Version vergleichbar
        (Get-VersionDate). Kein Abgleich mit Erscheinungsdaten.
    #>
    param([string] $Version, [string] $Bound)
    if ([string]::IsNullOrWhiteSpace($Bound) -or (Test-CommitLikeVersion $Bound.Trim())) { return $null }
    $installed = ConvertTo-NormalizedVersion $Version
    if (-not $installed) { return $null }
    $dateBound = ConvertFrom-DateBound -Bound $Bound -InstalledIsNormal ($installed.Parts[0] -lt 1900)
    if ($dateBound) {
        $installedDate = Get-VersionDate $installed
        if (-not $installedDate) { return $null }
        return [Math]::Sign(($installedDate - $dateBound).Ticks)
    }
    Compare-SoftwareVersion $Version $Bound
}
