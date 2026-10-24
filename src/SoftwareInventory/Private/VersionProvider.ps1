# Provider für die neueste Version, in fester Reihenfolge (docs/KONZEPT.md „Versionsabgleich“):
# winget (Inventardaten), GitHub Releases (Katalog), winget-Suche (unbestätigt).
# Jeder Provider liefert ein Ergebnis oder einen Grund, warum er nichts liefern konnte.

# Mehr Pakete mit passendem Namen gelten als mehrdeutig (jede Herstellerabfrage kostet Zeit).
$script:WingetSearchMaxCandidates = 5

function New-ProviderResult {
    param([string] $Source, [string] $LatestVersion, [bool] $Confirmed, [string] $Reason)
    [pscustomobject] @{ Source = $Source; LatestVersion = $LatestVersion; Confirmed = $Confirmed; Reason = $Reason }
}

function Get-WingetLatestVersion {
    # winget kennt das Paket: AvailableVersion gesetzt = Update, sonst aktuell laut winget.
    param($Record)
    if (-not $Record.WingetId) { return $null }
    $latest = if ($Record.AvailableVersion) { $Record.AvailableVersion } else { $Record.Version }
    New-ProviderResult -Source Winget -LatestVersion $latest -Confirmed $true
}

function Get-GitHubLatestVersion {
    <#
    .SYNOPSIS
        Neueste Release-Version aus dem GitHub-Repository des Katalogeintrags.
    .DESCRIPTION
        Liefert $null, wenn kein Repository bekannt ist, sonst ein Ergebnis oder einen Grund.
        $State.GitHubBlocked verhindert nach erreichtem Anfragelimit weitere Anfragen im selben Lauf.
    #>
    param($CatalogEntry, $Setting, [hashtable] $State)

    $github = Get-CatalogValue $CatalogEntry 'GitHub'
    if (-not $github) { return $null }
    if (-not (Test-ServiceEnabled -Name GitHub -Setting $Setting)) {
        return New-ProviderResult -Source GitHub -Reason 'Dienst GitHub nicht aktiviert'
    }
    if ($State.GitHubBlocked) { return New-ProviderResult -Source GitHub -Reason 'GitHub-Anfragelimit erreicht' }

    $repo = $github.Repository
    try {
        $release = Invoke-ServiceRequest -Service GitHub -Uri "https://api.github.com/repos/$repo/releases/latest" `
            -CacheKey "releases/latest/$repo" -MaxAge ([timespan]::FromHours(12)) -Setting $Setting
    }
    catch {
        $reason = Get-ServiceErrorReason $_
        if ($reason -eq 'RateLimit') {
            $State.GitHubBlocked = $true
            Write-Warning 'GitHub-Anfragelimit erreicht; weitere GitHub-Abfragen in diesem Lauf entfallen. Mit GITHUB_TOKEN gilt ein höheres Limit.'
            return New-ProviderResult -Source GitHub -Reason 'GitHub-Anfragelimit erreicht'
        }
        if ($reason -eq 'NotFound') { return New-ProviderResult -Source GitHub -Reason "Kein Release in $repo gefunden" }
        return New-ProviderResult -Source GitHub -Reason "GitHub nicht abrufbar: $($_.Exception.Message)"
    }

    $pattern = Get-CatalogValue $github 'TagPattern'
    if (-not $pattern) { $pattern = '^v?(?<version>\d.*)$' }
    if ([string] $release.tag_name -notmatch $pattern) {
        return New-ProviderResult -Source GitHub -Reason "Release-Tag '$($release.tag_name)' passt nicht zum Katalogmuster"
    }
    New-ProviderResult -Source GitHub -LatestVersion $Matches.version -Confirmed $true
}

function Find-WingetCandidate {
    # Kapselt Find-WinGetPackage (nur Quelle winget, die Store-Quelle fragt langsam online).
    # Liefert Name, Id, Version – ohne Hersteller, der kostet pro Paket eine eigene Abfrage.
    param([string] $Name)
    foreach ($pkg in Find-WinGetPackage -Query $Name -Source winget -ErrorAction Stop) {
        [pscustomobject] @{ Name = $pkg.Name; Id = $pkg.Id; Version = @($pkg.AvailableVersions)[0] }
    }
}

function Get-WingetPackagePublisher {
    # Hersteller eines winget-Pakets aus dem Manifest der angegebenen Version.
    param([string] $Id, [string] $Version)
    $pkg = Find-WinGetPackage -Id $Id -MatchOption Equals -Source winget -ErrorAction Stop | Select-Object -First 1
    if ($pkg) { $pkg.GetPackageVersionInfo($Version).Publisher }
}

function Test-WingetNameMatch {
    # „PSPad editor (x64)“ passt zu „PSPad“; „PSPadX“ nicht.
    param([string] $PackageName, [string] $Name)
    $PackageName -eq $Name -or $PackageName.StartsWith("$Name ", [StringComparison]::OrdinalIgnoreCase) -or
        $PackageName.StartsWith("$Name(", [StringComparison]::OrdinalIgnoreCase)
}

function Get-WingetSearchLatestVersion {
    <#
    .SYNOPSIS
        Sucht ein Programm ohne winget-ID im winget-Katalog: gleicher Name und gleicher Hersteller.
    .DESCRIPTION
        Ergebnis ist unbestätigt (Zuordnung nur über Name und Hersteller). Mehrdeutige Treffer
        werden nicht verwendet.
    #>
    param($Record, $Setting)

    if ($Record.WingetId) { return $null }
    if (-not (Test-ServiceEnabled -Name WingetSearch -Setting $Setting)) {
        return New-ProviderResult -Source WingetSearch -Reason 'Dienst WingetSearch nicht aktiviert'
    }
    if (-not (Get-Command Find-WinGetPackage -ErrorAction SilentlyContinue)) {
        return New-ProviderResult -Source WingetSearch -Reason 'winget-Suche nicht verfügbar (Microsoft.WinGet.Client fehlt)'
    }
    $publisher = Get-PublisherKey $Record.Publisher
    if (-not $publisher) { return New-ProviderResult -Source WingetSearch -Reason 'winget-Suche braucht einen Hersteller' }

    try {
        $named = @(Find-WingetCandidate -Name $Record.Name | Where-Object { Test-WingetNameMatch -PackageName $_.Name -Name $Record.Name })
        if ($named.Count -gt $script:WingetSearchMaxCandidates) {
            return New-ProviderResult -Source WingetSearch -Reason "winget-Suche mehrdeutig ($($named.Count) Pakete mit passendem Namen)"
        }
        $hits = @($named | Where-Object { (Get-PublisherKey (Get-WingetPackagePublisher -Id $_.Id -Version $_.Version)) -eq $publisher })
    }
    catch { return New-ProviderResult -Source WingetSearch -Reason "winget-Suche fehlgeschlagen: $(Protect-SecretText $_.Exception.Message)" }

    # Mehrere Pakete (z. B. x64 und x86) sind eindeutig, wenn sie dieselbe Version haben.
    $versions = @($hits | ForEach-Object Version | Select-Object -Unique)
    if ($versions.Count -eq 1) {
        return New-ProviderResult -Source WingetSearch -LatestVersion $versions[0] -Confirmed $false
    }
    if ($versions.Count -gt 1) { return New-ProviderResult -Source WingetSearch -Reason 'winget-Suche mehrdeutig' }
    New-ProviderResult -Source WingetSearch -Reason 'Kein passendes winget-Paket gefunden'
}
