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
