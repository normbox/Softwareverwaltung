function Test-SoftwareUpdate {
    <#
    .SYNOPSIS
        Ermittelt für erfasste Programme die neueste Version und ob ein Update verfügbar ist.
    .DESCRIPTION
        Provider in fester Reihenfolge, der erste Treffer gewinnt:
          1. winget   – aus den Inventardaten (AvailableVersion), keine zusätzliche Anfrage
          2. GitHub   – Releases laut Katalog; nur wenn der Dienst GitHub aktiviert ist
          3. winget-Suche – für Programme ohne winget-ID; nur wenn WingetSearch aktiviert ist;
                        Ergebnis gilt als unbestätigt
        CheckedAt nennt den ältesten benutzten Abruf (UTC), CheckStale, ob er älter als die eingestellte
        Haltbarkeit ist (z. B. offline nur Zwischenspeicher). -Refresh fragt ohne Zwischenspeicher neu.
        Status ist UpToDate, Outdated oder Unknown. Bei Unknown nennt Reason den Grund
        (z. B. „Dienst GitHub nicht aktiviert“, „keine Versionsquelle bekannt“).
    .EXAMPLE
        Get-SoftwareInventory | Test-SoftwareUpdate | Where-Object Status -eq Outdated
    .EXAMPLE
        Get-PortableSoftware | Test-SoftwareUpdate | Format-Table Name, InstalledVersion, LatestVersion, Status, Reason
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.UpdateStatus')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject,

        # Ohne Zwischenspeicher neu fragen (jede Antwort einmal je Lauf)
        [switch] $Refresh
    )

    begin {
        $ownsRefresh = $Refresh -and (Enter-CacheRefresh)
        $setting = Read-InventorySetting
        $catalog = Get-SoftwareCatalog
        $state = @{ GitHubBlocked = $false }
        $done = 0
    }
    process {
        foreach ($record in $InputObject) {
            if ($null -eq $record) { continue }
            $done++
            Write-CheckProgress -Id 3 -Activity ProgressCheckUpdates -Index $done -Total $InputObject.Count -Name $record.Name
            $match = Find-CatalogEntry -Record $record -Catalog $catalog
            $reasons = [System.Collections.Generic.List[object]]::new()
            $result = $null

            $providers = @(
                { Get-WingetLatestVersion -Record $record }
                { if ($match) { Get-GitHubLatestVersion -CatalogEntry $match.Entry -Setting $setting -State $state } }
                { Get-WingetSearchLatestVersion -Record $record -Setting $setting }
            )
            # Mitschrieb der benutzten Zwischenspeicher-Einträge für CheckedAt und den Index
            $outerTrace = $script:CheckTrace
            $script:CheckTrace = [System.Collections.Generic.List[object]]::new()
            try {
                foreach ($provider in $providers) {
                    $candidate = & $provider
                    if (-not $candidate) { continue }
                    if ($candidate.LatestVersion) { $result = $candidate; break }
                    if ($candidate.Reason) { $reasons.Add($candidate.Reason) }
                }
                $trace = @($script:CheckTrace)
            }
            finally { $script:CheckTrace = $outerTrace }

            Save-CheckIndex -Record $record -Kind Update -Trace $trace
            New-UpdateStatus -Record $record -Result $result -Reasons $reasons -CatalogId $(if ($match) { $match.Entry.Id }) -Trace $trace
        }
    }
    end { Write-CheckProgress -Id 3 -Activity ProgressCheckUpdates -Completed }
    clean { Exit-CacheRefresh $ownsRefresh }
}

function New-UpdateStatus {
    param($Record, $Result, [object[]] $Reasons, [string] $CatalogId, [object[]] $Trace)

    $status = 'Unknown'
    $reason = $null
    if (-not $Result) {
        # Mehrere Provider ohne Ergebnis: ein Grund NoLatestVersion mit allen Einzelgründen als Args.
        $reason = if ($Reasons.Count -gt 1) { New-InventoryMessage NoLatestVersion (, $Reasons) }
        elseif ($Reasons) { $Reasons[0] }
        else { New-InventoryMessage NoVersionSource }
    }
    else {
        $cmp = Compare-SoftwareVersion $Record.Version $Result.LatestVersion
        switch ($cmp) {
            -1 { $status = 'Outdated' }
            0 { $status = 'UpToDate' }
            1 { $status = 'UpToDate'; $reason = New-InventoryMessage InstalledNewer }
            default {
                $reason = if (-not (ConvertTo-NormalizedVersion $Record.Version)) { New-InventoryMessage InstalledVersionUnreadable $Record.Version }
                else { New-InventoryMessage FoundVersionUnreadable $Result.LatestVersion }
            }
        }
    }

    $summary = Get-CheckTraceSummary $Trace
    $checkedAt = if ($status -eq 'Unknown') { $null } elseif ($summary.CheckedAt) { $summary.CheckedAt } elseif ($Result) { [datetime]::UtcNow }
    [pscustomobject] @{
        PSTypeName       = 'SoftwareInventory.UpdateStatus'
        Name             = $Record.Name
        InstalledVersion = $Record.Version
        LatestVersion    = if ($Result) { $Result.LatestVersion } else { $null }
        Status           = $status
        Source           = if ($Result) { $Result.Source } else { $null }
        Confirmed        = if ($Result) { $Result.Confirmed } else { $false }
        Reason           = $reason
        # Ältester benutzter Abruf; winget-Daten kommen frisch aus dem Scan. Ohne Ergebnis leer.
        CheckedAt        = $checkedAt
        CheckStale       = [bool] ($checkedAt -and $summary.Stale)
        CatalogId        = $CatalogId
        Record           = $Record
    }
}
