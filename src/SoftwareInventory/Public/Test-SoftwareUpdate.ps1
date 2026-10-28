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
        [object[]] $InputObject
    )

    begin {
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
            foreach ($provider in $providers) {
                $candidate = & $provider
                if (-not $candidate) { continue }
                if ($candidate.LatestVersion) { $result = $candidate; break }
                if ($candidate.Reason) { $reasons.Add($candidate.Reason) }
            }

            New-UpdateStatus -Record $record -Result $result -Reasons $reasons -CatalogId $(if ($match) { $match.Entry.Id })
        }
    }
    end { Write-CheckProgress -Id 3 -Activity ProgressCheckUpdates -Completed }
}

function New-UpdateStatus {
    param($Record, $Result, [object[]] $Reasons, [string] $CatalogId)

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

    [pscustomobject] @{
        PSTypeName       = 'SoftwareInventory.UpdateStatus'
        Name             = $Record.Name
        InstalledVersion = $Record.Version
        LatestVersion    = if ($Result) { $Result.LatestVersion } else { $null }
        Status           = $status
        Source           = if ($Result) { $Result.Source } else { $null }
        Confirmed        = if ($Result) { $Result.Confirmed } else { $false }
        Reason           = $reason
        CatalogId        = $CatalogId
        Record           = $Record
    }
}
