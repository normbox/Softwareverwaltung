# Ab dieser geschätzten Dauer fragt die App vor einem Scan ohne Zwischenspeicher nach (Sekunden).
$script:LongRefreshSeconds = 300

function Get-RefreshEstimate {
    <#
    .SYNOPSIS
        Schätzt, wie lange eine Prüfung ohne Zwischenspeicher dauert.
    .DESCRIPTION
        Zählt die NVD-Anfragen (je Programm mit CPE-Zuordnung und lesbarer Version eine je CPE) und
        rechnet mit dem Mindestabstand der NVD: ohne Schlüssel 6 Sekunden, mit Schlüssel 0,6 Sekunden.
        Weitere Seiten und KEV-Nachfragen kommen hinzu; die Schätzung ist eine Untergrenze.
        Ist CIRCL eingeschaltet, lädt eine Prüfung ohne Zwischenspeicher den Bestand je CPE vollständig neu:
        alle Seiten (3 bzw. 1,5 Sekunden Abstand). Die Seitenzahl kommt aus der Größe des vorhandenen
        Bestands (etwa 34 KB je Seite); ohne Bestand zählt eine Seite, CirclUnknown nennt, für wie viele
        CPEs das gilt (dort kann es deutlich länger dauern). Mit NVD kommt je CPE eine NVD-Sammelabfrage
        für den Abgleich hinzu. Je CPE läuft es nacheinander: NVD-Versionssuche, CIRCL-Seiten, NVD-Abgleich;
        der Abstand der NVD überlappt dabei nur mit der Zeit der CIRCL-Seiten.
        NeedsConfirmation ist wahr, wenn NVD aktiviert ist und kein Schlüssel hinterlegt ist
        (ConfirmReason NvdWithoutKey) oder die Schätzung über 5 Minuten liegt (LongDuration): Dann fragt
        die App vor einem Scan ohne Zwischenspeicher nach und nennt die geschätzte Dauer.
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
        $cpePages = [System.Collections.Generic.List[int]]::new()   # CIRCL-Seiten je CPE (geschätzt)
        $circlUnknown = 0
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
            if (-not $version) { continue }
            foreach ($base in @($cpe.Cpe)) {
                $requests++
                $pages = Get-CirclPageEstimate $base
                if (-not $pages) { $circlUnknown++; $pages = 1 }
                $cpePages.Add($pages)
            }
        }
    }
    end {
        $nvd = Test-ServiceEnabled -Name NVD -Setting $setting
        $hasKey = [bool] (Get-ServiceSecret -Service NVD)
        $interval = if ($hasKey) { $script:ServiceInterval.NVD.WithKey } else { $script:ServiceInterval.NVD.Anonymous }
        $circl = Test-ServiceEnabled -Name CIRCL -Setting $setting
        $circlInterval = if ($circl -and (Get-ServiceSecret -Service CIRCL)) { $script:ServiceInterval.CIRCL.WithKey } else { $script:ServiceInterval.CIRCL.Anonymous }
        $nvdRequests = if ($nvd -and $circl) { 2 * $requests } elseif ($nvd) { $requests } else { 0 }
        $seconds = 0.0
        $circlPages = 0
        foreach ($pages in $cpePages) {
            $circlPages += $pages
            $circlSeconds = if ($circl) { $pages * $circlInterval } else { 0 }
            $add = if ($nvd -and $circl) { $interval + [Math]::Max($circlSeconds, $interval) }
                elseif ($nvd) { $interval }
                else { $circlSeconds }
            $seconds += $add
        }
        $confirmReason = if ($nvd -and -not $hasKey) { 'NvdWithoutKey' } elseif ($seconds -gt $script:LongRefreshSeconds) { 'LongDuration' } else { $null }
        [pscustomobject] [ordered]@{
            PSTypeName        = 'SoftwareInventory.RefreshEstimate'
            Programs          = $programs
            NvdEnabled        = $nvd
            NvdRequests       = $nvdRequests
            HasNvdKey         = $hasKey
            CirclEnabled      = $circl
            CirclRequests     = if ($circl) { $circlPages } else { 0 }
            CirclUnknown      = if ($circl) { $circlUnknown } else { 0 }
            Seconds           = [int] [Math]::Ceiling($seconds)
            NeedsConfirmation = [bool] $confirmReason
            ConfirmReason     = $confirmReason   # NvdWithoutKey, LongDuration oder $null
        }
    }
}
