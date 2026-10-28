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
    $ProgressPreference = 'SilentlyContinue'
    foreach ($pkg in Find-WinGetPackage -Query $Name -Source winget -ErrorAction Stop) {
        [pscustomobject] @{ Name = $pkg.Name; Id = $pkg.Id; Version = @($pkg.AvailableVersions)[0] }
    }
}

function Get-WingetPackagePublisher {
    # Hersteller eines winget-Pakets aus dem Manifest der angegebenen Version.
    param([string] $Id, [string] $Version)
    $ProgressPreference = 'SilentlyContinue'
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
    if ($Record.InstallType -eq 'MSIX') {
        return New-ProviderResult -Source WingetSearch -Reason 'Store-App: Updates über den Microsoft Store'
    }
    if (-not (Test-ServiceEnabled -Name WingetSearch -Setting $Setting)) {
        return New-ProviderResult -Source WingetSearch -Reason 'Dienst WingetSearch nicht aktiviert'
    }
    $problem = Get-WingetClientProblem -Command Find-WinGetPackage
    if ($problem) {
        return New-ProviderResult -Source WingetSearch -Reason "winget-Suche nicht verfügbar ($problem)"
    }
    $publisher = Get-PublisherKey $Record.Publisher
    if (-not $publisher) { return New-ProviderResult -Source WingetSearch -Reason 'winget-Suche braucht einen Hersteller' }

    try { $search = Get-WingetSearchResult -Name $Record.Name -PublisherKey $publisher }
    catch { return New-ProviderResult -Source WingetSearch -Reason "winget-Suche fehlgeschlagen: $(Protect-SecretText $_.Exception.Message)" }
    if ($search.Reason) { return New-ProviderResult -Source WingetSearch -Reason $search.Reason }

    # Mehrere Pakete (z. B. x64 und x86) sind eindeutig, wenn sie dieselbe Version haben.
    $versions = @($search.Versions | Select-Object -Unique)
    if ($versions.Count -gt 1) { return New-ProviderResult -Source WingetSearch -Reason 'winget-Suche mehrdeutig' }
    if ($versions.Count -eq 0) { return New-ProviderResult -Source WingetSearch -Reason 'Kein passendes winget-Paket gefunden' }

    if (-not (Test-PlausibleLatestVersion -Installed $Record.Version -Latest $versions[0])) {
        return New-ProviderResult -Source WingetSearch -Reason "winget-Treffer unplausibel (installiert $($Record.Version), gefunden $($versions[0]))"
    }
    New-ProviderResult -Source WingetSearch -LatestVersion $versions[0] -Confirmed $false
}

function Get-WingetSearchResult {
    <#
    .SYNOPSIS
        Versionen der winget-Pakete mit passendem Namen und Hersteller, 24 Stunden zwischengespeichert.
    .DESCRIPTION
        Liefert @{ Versions = ...; Reason = ... }. Fehler der Suche werden nicht gespeichert.
    #>
    param([string] $Name, [string] $PublisherKey)

    $key = "wingetsearch/$Name/$PublisherKey".ToLowerInvariant()
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($key)))
    $cacheFile = Join-Path (Join-Path (Get-CacheDirectory) 'WingetSearch') "$hash.json"
    $cached = Read-ServiceCache -Path $cacheFile -MaxAge ([timespan]::FromHours(24))
    if ($null -ne $cached) { return @{ Versions = @($cached.Versions); Reason = $cached.Reason } }

    $named = @(Find-WingetCandidate -Name $Name | Where-Object { Test-WingetNameMatch -PackageName $_.Name -Name $Name })
    $result = if ($named.Count -gt $script:WingetSearchMaxCandidates) {
        @{ Versions = @(); Reason = "winget-Suche mehrdeutig ($($named.Count) Pakete mit passendem Namen)" }
    }
    else {
        $hits = @($named | Where-Object { (Get-PublisherKey (Get-WingetPackagePublisher -Id $_.Id -Version $_.Version)) -eq $PublisherKey })
        @{ Versions = @($hits | ForEach-Object Version); Reason = $null }
    }
    Write-ServiceCache -Path $cacheFile -Content ([pscustomobject] $result | ConvertTo-Json -Compress)
    $result
}

function Test-PlausibleLatestVersion {
    <#
    .SYNOPSIS
        Prüft, ob eine nur über Name und Hersteller gefundene Version zur installierten passt.
    .DESCRIPTION
        Unplausibel ist eine „neueste“ Version mit kleinerer Hauptversion als installiert
        (z. B. 1.314 → 0.220) oder mit mehr als einer Hauptversion Abstand nach oben
        (z. B. 1.0 → 154.0). Ist eine Seite nicht lesbar, entscheidet der spätere Vergleich.
    #>
    param([string] $Installed, [string] $Latest)
    $a = ConvertTo-NormalizedVersion $Installed
    $b = ConvertTo-NormalizedVersion $Latest
    if (-not $a -or -not $b) { return $true }
    $diff = $b.Parts[0] - $a.Parts[0]
    $diff -ge 0 -and $diff -le 1
}
