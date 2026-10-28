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
        try {
            $updates = @(Test-SoftwareUpdate -InputObject $records.ToArray())
            $vulns = @(Get-SoftwareVulnerability -InputObject $records.ToArray())
        }
        finally { Exit-CacheRefresh $ownsRefresh }
        if ($updates.Count -ne $records.Count -or $vulns.Count -ne $records.Count) {
            throw (Get-LocalizedString 'ErrorInternalResultCount' $records.Count, $updates.Count, $vulns.Count)
        }
        $order = @{ Red = 0; Yellow = 1; Gray = 2; Green = 3 }

        $ratings = for ($i = 0; $i -lt $records.Count; $i++) {
            $u = $updates[$i]
            $v = $vulns[$i]
            $r = Get-RatingFromResult -UpdateStatus $u -VulnerabilityStatus $v
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
