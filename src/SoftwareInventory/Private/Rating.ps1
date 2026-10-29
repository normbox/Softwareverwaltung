# Ampel aus Versionsstand (Test-SoftwareUpdate) und Schwachstellen (Get-SoftwareVulnerability).
#   Rot   – aktiv ausgenutzte Lücke (KEV) oder kritische Lücke (CVSS >= 9), jeweils sicher betroffen
#   Gelb  – andere Lücken, „möglicherweise betroffen“ oder veraltete Version
#   Grün  – Sicherheitsprüfung gelaufen, nichts gefunden
#   Grau  – nicht geprüft; immer mit Grund
# Hinweise (Informational) färben nie.

$script:CriticalCvss = 9.0

function Get-RatingFromResult {
    <#
    .SYNOPSIS
        Bewertet ein Programm aus Update-Status und Schwachstellen-Status.
    .OUTPUTS
        @{ Rating = 'Red'|'Yellow'|'Green'|'Gray'; Reasons = SoftwareInventory.Message[] } (Code, Args, Text)
    #>
    param($UpdateStatus, $VulnerabilityStatus)

    $vulns = @(if ($VulnerabilityStatus) { $VulnerabilityStatus.Vulnerabilities }) | Where-Object { $_ }
    $affected = @($vulns | Where-Object Assessment -eq 'Affected')
    $possible = @($vulns | Where-Object Assessment -eq 'PossiblyAffected')
    $red = [System.Collections.Generic.List[object]]::new()
    $yellow = [System.Collections.Generic.List[object]]::new()

    foreach ($v in $affected) {
        if ($v.Kev) { $red.Add((New-InventoryMessage KevAffected $v.CveId)) }
        elseif ($null -ne $v.Score -and $v.Score -ge $script:CriticalCvss) { $red.Add((New-InventoryMessage CriticalCvss $v.CveId, $v.Score)) }
    }
    $other = @($affected | Where-Object { -not $_.Kev -and -not ($null -ne $_.Score -and $_.Score -ge $script:CriticalCvss) })
    if ($other) {
        # Neben roten Gründen heißen die übrigen „weitere“; bei einer Lücke steht ihre CVE im Text.
        $code = if ($red.Count) { 'OtherVulnerabilities' } else { 'KnownVulnerabilities' }
        $max = ($other | ForEach-Object { [double] $_.Score } | Measure-Object -Maximum).Maximum
        $single = if ($other.Count -eq 1) { $other[0].CveId }
        $yellow.Add($(if ($max) { New-InventoryMessage "${code}MaxCvss" (@($other.Count, $max) + @($single | Where-Object { $_ })) }
                else { New-InventoryMessage $code (@($other.Count) + @($single | Where-Object { $_ })) }))
    }
    foreach ($v in $possible) {
        # Widersprechen sich die Quellen, ist der Treffer nicht widerlegt, sondern Gelb mit eigenem Grund.
        if ($v.PSObject.Properties['SourcesDisagree'] -and $v.SourcesDisagree) { $yellow.Add((New-InventoryMessage SourcesDisagree $v.CveId)); continue }
        $code = if ($v.Kev) { 'PossiblyAffectedKev' } else { 'PossiblyAffected' }
        $yellow.Add((New-InventoryMessage $code $v.CveId, $v.Note))
    }
    if ($UpdateStatus -and $UpdateStatus.Status -eq 'Outdated') {
        $code = if ($UpdateStatus.Confirmed) { 'UpdateAvailable' } else { 'UpdateAvailableUnconfirmed' }
        $yellow.Add((New-InventoryMessage $code $UpdateStatus.InstalledVersion, $UpdateStatus.LatestVersion, $UpdateStatus.Source))
    }

    # Widerlegte KEV-Treffer färben nie, werden aber als Grund genannt (nachvollziehbar statt still).
    $refuted = @(@(if ($VulnerabilityStatus -and $VulnerabilityStatus.PSObject.Properties['Refuted']) { $VulnerabilityStatus.Refuted }) | Where-Object { $_ } | ForEach-Object Note)

    if ($red.Count) { return @{ Rating = 'Red'; Reasons = @(@($red) + @($yellow) + $refuted) } }
    if ($yellow.Count) { return @{ Rating = 'Yellow'; Reasons = @(@($yellow) + $refuted) } }

    if ($VulnerabilityStatus -and $VulnerabilityStatus.Status -eq 'Checked') {
        $reasons = @(New-InventoryMessage NoFindings) + $refuted
        if ($UpdateStatus -and $UpdateStatus.Status -eq 'UpToDate') { $reasons += New-InventoryMessage VersionCurrent }
        return @{ Rating = 'Green'; Reasons = @($reasons) }
    }

    # Grau: immer mit Grund
    $gray = @()
    $gray += if ($VulnerabilityStatus -and $VulnerabilityStatus.Reason) { New-InventoryMessage NotCheckedBecause (, $VulnerabilityStatus.Reason) } else { New-InventoryMessage NotChecked }
    $gray += $refuted
    if ($UpdateStatus -and $UpdateStatus.Status -eq 'Unknown' -and $UpdateStatus.Reason) { $gray += New-InventoryMessage VersionUnknownBecause (, $UpdateStatus.Reason) }
    elseif ($UpdateStatus -and $UpdateStatus.Status -eq 'UpToDate') { $gray += New-InventoryMessage VersionCurrent }
    @{ Rating = 'Gray'; Reasons = @($gray) }
}
