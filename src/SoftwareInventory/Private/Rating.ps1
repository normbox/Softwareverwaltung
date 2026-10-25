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
        @{ Rating = 'Red'|'Yellow'|'Green'|'Gray'; Reasons = [string[]] }
    #>
    param($UpdateStatus, $VulnerabilityStatus)

    $vulns = @(if ($VulnerabilityStatus) { $VulnerabilityStatus.Vulnerabilities }) | Where-Object { $_ }
    $affected = @($vulns | Where-Object Assessment -eq 'Affected')
    $possible = @($vulns | Where-Object Assessment -eq 'PossiblyAffected')
    $red = [System.Collections.Generic.List[string]]::new()
    $yellow = [System.Collections.Generic.List[string]]::new()

    foreach ($v in $affected) {
        if ($v.Kev) { $red.Add("Aktiv ausgenutzte Lücke $($v.CveId) (CISA KEV)") }
        elseif ($null -ne $v.Score -and $v.Score -ge $script:CriticalCvss) { $red.Add("Kritische Lücke $($v.CveId) (CVSS $($v.Score))") }
    }
    $other = @($affected | Where-Object { -not $_.Kev -and -not ($null -ne $_.Score -and $_.Score -ge $script:CriticalCvss) })
    if ($other) {
        $max = ($other | ForEach-Object { [double] $_.Score } | Measure-Object -Maximum).Maximum
        $yellow.Add("$($other.Count) bekannte Lücke(n)" + $(if ($max) { ", höchster CVSS $max" }))
    }
    foreach ($v in $possible) {
        $kev = if ($v.Kev) { 'aktiv ausgenutzt, ' } else { '' }
        $yellow.Add("Möglicherweise betroffen: $($v.CveId) ($kev$($v.Note -replace '^Aktiv ausgenutzt; ', ''))")
    }
    if ($UpdateStatus -and $UpdateStatus.Status -eq 'Outdated') {
        $unconfirmed = if ($UpdateStatus.Confirmed) { '' } else { ', unbestätigt' }
        $yellow.Add("Update verfügbar: $($UpdateStatus.InstalledVersion) → $($UpdateStatus.LatestVersion) (Quelle $($UpdateStatus.Source)$unconfirmed)")
    }

    if ($red.Count) { return @{ Rating = 'Red'; Reasons = [string[]] @($red) + @($yellow) } }
    if ($yellow.Count) { return @{ Rating = 'Yellow'; Reasons = [string[]] $yellow } }

    if ($VulnerabilityStatus -and $VulnerabilityStatus.Status -eq 'Checked') {
        $reasons = @('Sicherheitsprüfung ohne Befund')
        if ($UpdateStatus -and $UpdateStatus.Status -eq 'UpToDate') { $reasons += 'Version aktuell' }
        return @{ Rating = 'Green'; Reasons = [string[]] $reasons }
    }

    # Grau: immer mit Grund
    $gray = @()
    $gray += if ($VulnerabilityStatus -and $VulnerabilityStatus.Reason) { "Nicht auf Lücken geprüft: $($VulnerabilityStatus.Reason)" } else { 'Nicht auf Lücken geprüft' }
    if ($UpdateStatus -and $UpdateStatus.Status -eq 'Unknown' -and $UpdateStatus.Reason) { $gray += "Versionsstand unbekannt: $($UpdateStatus.Reason)" }
    elseif ($UpdateStatus -and $UpdateStatus.Status -eq 'UpToDate') { $gray += 'Version aktuell' }
    @{ Rating = 'Gray'; Reasons = [string[]] $gray }
}
