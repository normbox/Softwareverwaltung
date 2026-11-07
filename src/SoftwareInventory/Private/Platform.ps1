# Plattformfilter: Lücken, die laut Quelle nur andere Betriebssysteme betreffen (macOS, iOS, Android,
# Linux, ChromeOS), zählen unter Windows nicht als Treffer. Ausgeschlossen wird nur, was eindeutig einer
# dieser Plattformen zugeordnet ist; alles Unbekannte (z. B. „unknown“, „x64-based systems“, Anwendungen
# als Umgebung) zählt weiter (lieber ein Fehlalarm mehr). Plattformnamen sind Eigennamen und werden
# nicht übersetzt.

function Get-PlatformFromText {
    <#
    .SYNOPSIS
        Plattform zu einer Angabe der Quellen: 'Windows', der Name einer anderen bekannten Plattform oder $null (unbekannt).
    .DESCRIPTION
        Angaben sind z. B. das CPE-Feld target_sw („iphone_os“), das Produkt einer Betriebssystem-CPE
        („mac_os_x“, „windows_10“) oder ein Eintrag von „platforms“ im CVE-5-Datensatz („Linux(R580)“,
        „Windows Server 2019“). Unterstrich und Leerzeichen gelten gleich.
    #>
    param([string] $Text)
    $t = (($Text -replace '\\', '') -replace '[_\s]+', ' ').Trim().ToLowerInvariant()
    if (-not $t -or $t -in '*', '-') { return $null }
    switch -Regex ($t) {
        '^windows' { return 'Windows' }
        '^android( |$|\()' { return 'Android' }
        '^(iphone os|ios)( |$|\()' { return 'iOS' }
        '^ipados( |$|\()' { return 'iPadOS' }
        '^(macos|mac os x|mac os|macosx|os x)( |$|\()' { return 'macOS' }
        '^(linux|linux kernel)( |$|\()' { return 'Linux' }
        '^(chrome os|chromeos|chromium os)( |$|\()' { return 'ChromeOS' }
    }
    $null
}

function Get-CpePlatform {
    # Plattform einer Betriebssystem-CPE (Teil „o“), z. B. cpe:2.3:o:apple:macos:… → macOS; sonst $null.
    param([string] $Criteria)
    $parts = $Criteria -split '(?<!\\):'
    if ($parts.Count -lt 5 -or $parts[2] -ne 'o') { return $null }
    $product = ($parts[4] -replace '\\', '').ToLowerInvariant()
    $platform = Get-PlatformFromText $product
    if ($platform) { return $platform }
    # Linux-Distributionen (ubuntu_linux, debian_linux, enterprise_linux)
    if ($product -match '_linux$') { return 'Linux' }
    $null
}

function Get-CpeTargetPlatform {
    # Plattform aus dem CPE-Feld target_sw (z. B. „android“ bei Firefox für Android); $null, wenn leer oder unbekannt.
    param([string] $Criteria)
    $parts = $Criteria -split '(?<!\\):'
    if ($parts.Count -lt 11) { return $null }
    Get-PlatformFromText $parts[10]
}

function Get-NvdMatchOtherPlatform {
    <#
    .SYNOPSIS
        Andere Plattformen, auf die ein cpeMatch-Eintrag des Produkts laut NVD beschränkt ist; leer, wenn er (auch) für Windows gilt oder es unklar ist.
    .DESCRIPTION
        Beschränkt ist ein Eintrag, wenn sein target_sw eine andere Plattform nennt oder seine
        Konfiguration UND-verknüpft ist und die Umgebung (Einträge mit vulnerable=false) nur aus
        Betriebssystemen anderer Plattformen besteht. Eine Umgebung mit Windows, einer Anwendung,
        einem unbekannten Betriebssystem oder negierten Knoten beschränkt nicht.
    #>
    param($Match, $Configuration)
    $target = Get-CpeTargetPlatform $Match.criteria
    if ($target -and $target -ne 'Windows') { return @($target) }
    if (-not $Configuration -or $Configuration.PSObject.Properties['operator']?.Value -ne 'AND' -or $Configuration.PSObject.Properties['negate']?.Value) { return }
    $nodes = @($Configuration.nodes) | Where-Object { $_ }
    if ($nodes | Where-Object { $_.PSObject.Properties['negate']?.Value }) { return }
    $environment = @($nodes | ForEach-Object { @($_.cpeMatch) } | Where-Object { $_ -and -not $_.vulnerable })
    if (-not $environment) { return }
    $platforms = @(foreach ($m in $environment) { Get-CpePlatform $m.criteria }) | Where-Object { $_ }
    if (@($platforms).Count -ne $environment.Count -or 'Windows' -in $platforms) { return }
    @($platforms | Select-Object -Unique)
}

# Plattform im Produktnamen eines CVE-5-Eintrags, nur in festen Formen („Firefox for Android“, „… on iOS“).
$script:ProductNamePlatformPattern = '(?i)\b(?:for|on)\s+(android|ipados|ios|iphone|macos|mac\s+os\s+x|mac\s+os|mac|os\s+x|linux|chrome\s?os)\b'

function Get-ProductNamePlatform {
    # Andere Plattform aus dem Produktnamen, z. B. „Firefox for Android“ → Android; sonst $null.
    param([string] $Product)
    $m = [regex]::Match($Product, $script:ProductNamePlatformPattern)
    if (-not $m.Success) { return $null }
    $word = $m.Groups[1].Value.ToLowerInvariant() -replace '\s+', ' '
    switch ($word) {
        'mac' { return 'macOS' }
        'iphone' { return 'iOS' }
    }
    Get-PlatformFromText $word
}

function Get-Cve5BlockOtherPlatform {
    <#
    .SYNOPSIS
        Andere Plattformen, auf die ein affected-Eintrag eines CVE-5-Datensatzes beschränkt ist; leer, wenn er (auch) für Windows gilt oder es unklar ist.
    .DESCRIPTION
        Beschränkt ist der Eintrag, wenn alle Angaben unter „platforms“ andere Plattformen sind, wenn
        alle passenden CPEs des Eintrags im Feld target_sw eine andere Plattform nennen, oder – nur bei
        Zuordnung über einen ähnlichen Namen, nicht bei genau gleichem Produkt – wenn der Produktname
        eine andere Plattform nennt („Firefox for Android“).
    #>
    param($Block, [string[]] $MatchedCpe = @(), [switch] $NameOnly)
    $listed = @($Block.PSObject.Properties['platforms']?.Value) | Where-Object { $_ }
    if ($listed) {
        $platforms = @($listed | ForEach-Object { Get-PlatformFromText ([string] $_) } | Where-Object { $_ })
        if ($platforms.Count -eq @($listed).Count -and 'Windows' -notin $platforms) { return @($platforms | Select-Object -Unique) }
    }
    if ($MatchedCpe) {
        $targets = @($MatchedCpe | ForEach-Object { Get-CpeTargetPlatform ([string] $_) } | Where-Object { $_ })
        if ($targets.Count -eq @($MatchedCpe).Count -and 'Windows' -notin $targets) { return @($targets | Select-Object -Unique) }
    }
    if ($NameOnly) {
        $named = Get-ProductNamePlatform ([string] $Block.PSObject.Properties['product']?.Value)
        if ($named) { return @($named) }
    }
}
