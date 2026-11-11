function Get-SecurityRating {
    <#
    .SYNOPSIS
        Bewertet erfasste Programme mit einer Ampel (Rot, Gelb, Grün, Grau).
    .DESCRIPTION
        Ermittelt für jedes Programm Versionsstand (Test-SoftwareUpdate) und Schwachstellen
        (Get-SoftwareVulnerability) mit den aktivierten Diensten und leitet daraus ab:
          Red    – aktiv ausgenutzte Lücke (KEV) oder kritische Lücke (CVSS ab 9), sicher betroffen
          Yellow – andere Lücken, „möglicherweise betroffen“ oder Update verfügbar
          Green  – Sicherheitsprüfung gelaufen, nichts gefunden
          Gray   – nicht auf Lücken geprüft (z. B. keine CPE, Dienst nicht aktiviert)
        Reasons nennt immer die Gründe, bei Grau, warum nicht geprüft wurde. CheckedAt ist der ältere
        Prüfzeitpunkt von Version und Lücken (UTC), CheckStale zeigt an, dass Daten älter als die
        eingestellte Haltbarkeit verwendet wurden. -Refresh prüft ohne Zwischenspeicher.
    .EXAMPLE
        Get-SoftwareInventory | Get-SecurityRating | Where-Object Rating -in 'Red', 'Yellow'
    .EXAMPLE
        @(Get-SoftwareInventory) + @(Get-PortableSoftware) | Get-SecurityRating | Export-SecurityReport -Path .\bericht.html
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SecurityRating')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject,

        # Ohne Zwischenspeicher neu prüfen (jede Antwort einmal je Lauf, der KEV-Katalog also einmal)
        [switch] $Refresh
    )

    begin { $records = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $InputObject) { if ($null -ne $item) { $records.Add($item) } } }
    end {
        if (-not $records.Count) { return }
        # Ein Aufruf je Funktion mit der ganzen Liste: Ergebnisse kommen je Datensatz in derselben Reihenfolge.
        $ownsRefresh = $Refresh -and (Enter-CacheRefresh)
        # Index je Programm einmal am Ende schreiben (Update- und Lückenprüfung zusammen), nur bei Änderung.
        $ownsIndex = Enter-CheckIndexBatch
        try {
            $updates = @(Test-SoftwareUpdate -InputObject $records.ToArray())
            $vulns = @(Get-SoftwareVulnerability -InputObject $records.ToArray())
        }
        finally {
            Exit-CheckIndexBatch $ownsIndex
            Exit-CacheRefresh $ownsRefresh
        }
        if ($updates.Count -ne $records.Count -or $vulns.Count -ne $records.Count) {
            throw (Get-LocalizedString 'ErrorInternalResultCount' $records.Count, $updates.Count, $vulns.Count)
        }
        $order = @{ Red = 0; Yellow = 1; Gray = 2; Green = 3 }
        $catalog = Get-SoftwareCatalog

        $ratings = for ($i = 0; $i -lt $records.Count; $i++) {
            $u = $updates[$i]
            $v = $vulns[$i]
            $r = Get-RatingFromResult -UpdateStatus $u -VulnerabilityStatus $v
            # Verwaister Eintrag: Grau mit eigenem Grund statt „nicht geprüft“; neuere Installation daneben als Hinweis.
            if (@(Get-RecordValue $records[$i] 'Flags') -contains 'Orphaned') {
                $newer = Find-NewerInstallation -Record $records[$i] -Candidate $records -Catalog $catalog
                $r = @{ Rating = 'Gray'; Reasons = @(@(New-InventoryMessage OrphanedEntry) + @(if ($newer) { New-InventoryMessage NewerInstallNextTo $newer.Name, $newer.Version })) }
            }
            # Treffer aus Nutzungsspuren, deren Laufwerk fehlt: Grund zuerst nennen (statt still zu verwerfen).
            if (@(Get-RecordValue $records[$i] 'Flags') -contains 'PathUnreachable') {
                $r.Reasons = @(@(New-InventoryMessage PathUnreachable) + @($r.Reasons))
            }
            [pscustomobject] @{
                PSTypeName          = 'SoftwareInventory.SecurityRating'
                Name                = $records[$i].Name
                Version             = $records[$i].Version
                Rating              = $r.Rating
                Reasons             = $r.Reasons
                LatestVersion       = $u.LatestVersion
                # Geprüft: das Ältere von Versions- und Sicherheitsprüfung; veraltet, wenn eine davon es ist.
                CheckedAt           = @((Get-RecordValue $u 'CheckedAt'), (Get-RecordValue $v 'CheckedAt')) | Where-Object { $_ } | Sort-Object | Select-Object -First 1
                UpdateCheckedAt     = Get-RecordValue $u 'CheckedAt'
                VulnerabilityCheckedAt = Get-RecordValue $v 'CheckedAt'
                CheckStale          = [bool] ((Get-RecordValue $u 'CheckStale') -or (Get-RecordValue $v 'CheckStale'))
                UpdateStatus        = $u
                VulnerabilityStatus = $v
                Record              = $records[$i]
            }
        }
        $ratings | Sort-Object @{ Expression = { $order[$_.Rating] } }, Name
    }
}

function Find-NewerInstallation {
    <#
    .SYNOPSIS
        Ein anderer, nicht verwaister Eintrag desselben Programms mit neuerer Version; sonst $null.
    .DESCRIPTION
        Dasselbe Programm: gleicher Katalogeintrag oder gleicher Name ohne angehängte Versionsnummer
        („Jan 0.5.16“ = „Jan“). Nur ein Hinweis, kein Kriterium für „verwaist“.
    #>
    param($Record, [object[]] $Candidate, $Catalog)
    $baseName = { param($n) ([string] $n -replace '\s+v?\d+(?:\.\d+)*\s*$', '').Trim() }
    $ownName = & $baseName $Record.Name
    $ownMatch = Find-CatalogEntry -Record $Record -Catalog $Catalog
    $ownId = if ($ownMatch) { $ownMatch.Entry.Id }
    $found = foreach ($c in $Candidate) {
        if ([object]::ReferenceEquals($c, $Record) -or @(Get-RecordValue $c 'Flags') -contains 'Orphaned') { continue }
        $cmp = Compare-SoftwareVersion $c.Version $Record.Version
        if ($null -eq $cmp -or $cmp -le 0) { continue }
        $sameName = (& $baseName $c.Name) -eq $ownName
        $match = if (-not $sameName -and $ownId) { Find-CatalogEntry -Record $c -Catalog $Catalog }
        if ($sameName -or ($match -and $match.Entry.Id -eq $ownId)) { $c }
    }
    $best = $null
    foreach ($c in @($found)) { if (-not $best -or (Compare-SoftwareVersion $c.Version $best.Version) -gt 0) { $best = $c } }
    $best
}
