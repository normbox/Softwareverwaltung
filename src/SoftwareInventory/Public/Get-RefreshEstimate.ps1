function Get-RefreshEstimate {
    <#
    .SYNOPSIS
        Schätzt, wie lange eine Prüfung ohne Zwischenspeicher dauert.
    .DESCRIPTION
        Zählt die NVD-Anfragen (je Programm mit CPE-Zuordnung und lesbarer Version eine je CPE) und
        rechnet mit dem Mindestabstand der NVD: ohne Schlüssel 6 Sekunden, mit Schlüssel 0,6 Sekunden.
        Weitere Seiten und KEV-Nachfragen kommen hinzu; die Schätzung ist eine Untergrenze.
        NeedsConfirmation ist wahr, wenn NVD aktiviert ist und kein Schlüssel hinterlegt ist: Dann fragt
        die App vor einem Scan ohne Zwischenspeicher nach.
    .EXAMPLE
        Get-SoftwareInventory | Get-RefreshEstimate
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.RefreshEstimate')]
    param(
        # Datensätze oder Ergebnisse von Get-SecurityRating
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject
    )

    begin {
        $setting = Read-InventorySetting
        $catalog = Get-SoftwareCatalog
        $userMap = Read-CpeMapping
        $programs = 0
        $requests = 0
    }
    process {
        foreach ($item in $InputObject) {
            $record = Get-ActionRecord $item
            if (-not $record) { continue }
            $programs++
            $match = Find-CatalogEntry -Record $record -Catalog $catalog
            $entry = if ($match) { $match.Entry }
            $cpe = Get-RecordCpe -Record $record -CatalogEntry $entry -UserMap $userMap
            if (-not $cpe) { continue }
            $version = ConvertTo-CpeVersion $record.Version -Pattern $(if ($entry) { Get-CatalogValue $entry 'CpeVersionPattern' })
            if ($version) { $requests += @($cpe.Cpe).Count }
        }
    }
    end {
        $nvd = Test-ServiceEnabled -Name NVD -Setting $setting
        $hasKey = [bool] (Get-ServiceSecret -Service NVD)
        $interval = if ($hasKey) { $script:ServiceInterval.NVD.WithKey } else { $script:ServiceInterval.NVD.Anonymous }
        [pscustomobject] [ordered]@{
            PSTypeName        = 'SoftwareInventory.RefreshEstimate'
            Programs          = $programs
            NvdEnabled        = $nvd
            NvdRequests       = if ($nvd) { $requests } else { 0 }
            HasNvdKey         = $hasKey
            Seconds           = if ($nvd) { [int] [Math]::Ceiling($requests * $interval) } else { 0 }
            NeedsConfirmation = $nvd -and -not $hasKey
        }
    }
}
