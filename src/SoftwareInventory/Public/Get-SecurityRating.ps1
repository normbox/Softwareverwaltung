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
        Reasons nennt immer die Gründe, bei Grau, warum nicht geprüft wurde.
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
        [object[]] $InputObject
    )

    begin { $records = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $InputObject) { if ($null -ne $item) { $records.Add($item) } } }
    end {
        if (-not $records.Count) { return }
        # Ein Aufruf je Funktion mit der ganzen Liste: Ergebnisse kommen je Datensatz in derselben Reihenfolge.
        $updates = @(Test-SoftwareUpdate -InputObject $records.ToArray())
        $vulns = @(Get-SoftwareVulnerability -InputObject $records.ToArray())
        if ($updates.Count -ne $records.Count -or $vulns.Count -ne $records.Count) {
            throw "Interner Fehler: $($records.Count) Programme, aber $($updates.Count) Update- und $($vulns.Count) Schwachstellen-Ergebnisse."
        }
        $order = @{ Red = 0; Yellow = 1; Gray = 2; Green = 3 }

        $ratings = for ($i = 0; $i -lt $records.Count; $i++) {
            $u = $updates[$i]
            $v = $vulns[$i]
            $r = Get-RatingFromResult -UpdateStatus $u -VulnerabilityStatus $v
            # Treffer aus Nutzungsspuren, deren Laufwerk fehlt: Grund zuerst nennen (statt still zu verwerfen).
            if (@(Get-RecordValue $records[$i] 'Flags') -contains 'PathUnreachable') {
                $r.Reasons = [string[]] (@(Get-LocalizedString 'RatingReasonPathUnreachable') + @($r.Reasons))
            }
            [pscustomobject] @{
                PSTypeName          = 'SoftwareInventory.SecurityRating'
                Name                = $records[$i].Name
                Version             = $records[$i].Version
                Rating              = $r.Rating
                Reasons             = $r.Reasons
                LatestVersion       = $u.LatestVersion
                UpdateStatus        = $u
                VulnerabilityStatus = $v
                Record              = $records[$i]
            }
        }
        $ratings | Sort-Object @{ Expression = { $order[$_.Rating] } }, Name
    }
}
