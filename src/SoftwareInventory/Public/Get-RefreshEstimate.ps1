function Get-RefreshEstimate {
    <#
    .SYNOPSIS
        Schätzt, wie lange eine Prüfung ohne Zwischenspeicher dauert.
    .DESCRIPTION
        Zählt die NVD-Anfragen (je Programm mit CPE-Zuordnung und lesbarer Version eine je CPE) und
        rechnet mit dem Mindestabstand der NVD: ohne Schlüssel 6 Sekunden, mit Schlüssel 0,6 Sekunden.
        Weitere Seiten und KEV-Nachfragen kommen hinzu; die Schätzung ist eine Untergrenze.
        Ist CIRCL eingeschaltet, kommt je CPE eine CIRCL-Anfrage hinzu (3 bzw. 1,5 Sekunden Abstand),
        mit NVD zusätzlich je CPE eine NVD-Sammelabfrage für den Abgleich der beiden Quellen.
        Beide Dienste warten nur auf ihren eigenen Abstand, daher zählt die längere der beiden Zeiten.
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
        $circl = Test-ServiceEnabled -Name CIRCL -Setting $setting
        $circlInterval = if ($circl -and (Get-ServiceSecret -Service CIRCL)) { $script:ServiceInterval.CIRCL.WithKey } else { $script:ServiceInterval.CIRCL.Anonymous }
        $nvdRequests = if ($nvd -and $circl) { 2 * $requests } elseif ($nvd) { $requests } else { 0 }
        $nvdSeconds = $nvdRequests * $interval
        $circlSeconds = if ($circl) { $requests * $circlInterval } else { 0 }
        [pscustomobject] [ordered]@{
            PSTypeName        = 'SoftwareInventory.RefreshEstimate'
            Programs          = $programs
            NvdEnabled        = $nvd
            NvdRequests       = $nvdRequests
            HasNvdKey         = $hasKey
            CirclEnabled      = $circl
            CirclRequests     = if ($circl) { $requests } else { 0 }
            Seconds           = [int] [Math]::Ceiling([Math]::Max($nvdSeconds, $circlSeconds))
            NeedsConfirmation = $nvd -and -not $hasKey
        }
    }
}
