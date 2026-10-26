function Invoke-AdvisorTool {
    <#
    .SYNOPSIS
        Führt ein Tool des KI-Beraters aus und liefert das Ergebnis als bereinigtes JSON.
    .DESCRIPTION
        Für die Gesprächsschleife: Das Modell nennt Tool und Argumente (JSON), diese Funktion prüft
        die Argumente, liest die Daten und gibt Content (JSON-Text für das Modell, ohne Benutzerpfade,
        Namen und Schlüssel) zurück. Fehler kommen als Ok = $false mit verständlicher Meldung im
        Content, damit das Modell sich korrigieren kann; es wird nie eine Ausnahme geworfen.
        propose_update und propose_uninstall führen nichts aus: Proposal enthält den Vorschlag
        (mit der Bewertung als Rating) für die Oberfläche, die den Benutzer bestätigen lässt.
    .PARAMETER Name
        Name des Tools (siehe Get-AdvisorTool).
    .PARAMETER ArgumentsJson
        Argumente als JSON-Objekt, wie sie das Modell liefert.
    .EXAMPLE
        (Invoke-AdvisorTool -Name get_inventory -ArgumentsJson '{"rating":"Red"}').Content
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorToolResult')]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [AllowEmptyString()]
        [string] $ArgumentsJson = '{}'
    )

    $fail = { param($Message) New-AdvisorToolResult -Name $Name -Ok $false -Data ([ordered]@{ error = $Message }) }
    if (-not $script:AdvisorTools.Contains($Name)) {
        return & $fail "Unbekanntes Tool '$Name'. Verfügbar: $($script:AdvisorTools.Keys -join ', ')."
    }
    try {
        $arguments = if ([string]::IsNullOrWhiteSpace($ArgumentsJson)) { @{} } else { $ArgumentsJson | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
        if ($arguments -isnot [hashtable]) { throw 'kein Objekt' }
    }
    catch {
        return & $fail 'Die Argumente sind kein gültiges JSON-Objekt.'
    }

    # Programm über die id aus get_inventory
    $rating = $null
    if ($script:AdvisorTools[$Name].Parameters.required -contains 'id') {
        $id = [string] $arguments['id']
        if ($id -notmatch '^p-[0-9a-f]{12}$') { return & $fail "Ungültige id '$id'. Erst get_inventory aufrufen und die dortige id verwenden." }
        $rating = Find-AdvisorRating $id
        if (-not $rating) { return & $fail "Kein Programm mit id '$id' im letzten Scan. Erst get_inventory aufrufen." }
    }

    try {
        switch ($Name) {
            'get_inventory' {
                $limit = 50
                if ($arguments.ContainsKey('limit')) {
                    $limit = $arguments['limit'] -as [int]
                    if (-not $limit -or $limit -lt 1 -or $limit -gt $script:AdvisorMaxListItems) { return & $fail "limit muss zwischen 1 und $($script:AdvisorMaxListItems) liegen." }
                }
                $ratingFilter = [string] $arguments['rating']
                if ($ratingFilter -and $ratingFilter -notin 'Red', 'Yellow', 'Gray', 'Green') { return & $fail 'rating muss Red, Yellow, Gray oder Green sein.' }
                $filter = [string] $arguments['filter']
                $all = @(Get-AdvisorContextRating)
                $matching = @($all | Where-Object {
                        (-not $ratingFilter -or $_.Rating -eq $ratingFilter) -and
                        (-not $arguments['updates_only'] -or ($_.UpdateStatus -and $_.UpdateStatus.Status -eq 'Outdated')) -and
                        (-not $filter -or $_.Name -like "*$([WildcardPattern]::Escape($filter))*" -or (Get-RecordValue $_.Record 'Publisher') -like "*$([WildcardPattern]::Escape($filter))*")
                    })
                $order = @{ Red = 0; Yellow = 1; Gray = 2; Green = 3 }
                $programs = @($matching | Sort-Object @{ Expression = { $order[$_.Rating] } }, Name | Select-Object -First $limit | ForEach-Object { ConvertTo-AdvisorSummary $_ })
                New-AdvisorToolResult -Name $Name -Ok $true -Data ([ordered]@{ programs_in_scan = $all.Count; matching = $matching.Count; returned = $programs.Count; programs = $programs })
            }
            'get_program_details' {
                New-AdvisorToolResult -Name $Name -Ok $true -Data (ConvertTo-AdvisorDetail $rating)
            }
            'check_latest_version' {
                $u = Test-SoftwareUpdate -InputObject $rating.Record
                New-AdvisorToolResult -Name $Name -Ok $true -Data ([ordered]@{
                        status = $u.Status; installed_version = $u.InstalledVersion; latest_version = $u.LatestVersion
                        source = $u.Source; confirmed = $u.Confirmed; reason = $u.Reason
                    })
            }
            'search_vulnerabilities' {
                $v = Get-SoftwareVulnerability -InputObject $rating.Record
                New-AdvisorToolResult -Name $Name -Ok $true -Data ([ordered]@{
                        status = $v.Status; reason = $v.Reason; notes = @($v.Notes)
                        vulnerabilities = @($v.Vulnerabilities | Select-Object -First 25 | ForEach-Object {
                                [ordered]@{ cve = $_.CveId; assessment = $_.Assessment; kev = [bool] $_.Kev; cvss = $_.Score; epss = $_.Epss; note = $_.Note }
                            })
                        refuted = @($v.Refuted | ForEach-Object Note)
                    })
            }
            { $_ -in 'propose_update', 'propose_uninstall' } {
                $reason = ([string] $arguments['reason']).Trim()
                if (-not $reason) { return & $fail 'reason fehlt: Begründung für den Benutzer angeben.' }
                if ($reason.Length -gt 500) { $reason = $reason.Substring(0, 500) }
                $action = if ($Name -eq 'propose_update') { 'Update' } else { 'Uninstall' }
                if ($action -eq 'Update' -and -not ($rating.UpdateStatus -and $rating.UpdateStatus.Status -eq 'Outdated')) {
                    return & $fail "Für '$($rating.Name)' ist kein Update bekannt. Erst check_latest_version aufrufen."
                }
                $proposal = [pscustomobject] [ordered]@{
                    PSTypeName = 'SoftwareInventory.AdvisorProposal'
                    ProposalId = [guid]::NewGuid().ToString()
                    Action     = $action
                    ProgramId  = Get-AdvisorProgramId $rating.Record
                    Name       = $rating.Name
                    Reason     = Protect-PrivateText $reason
                    Rating     = $rating   # nur für die Oberfläche, geht nicht an das Modell
                }
                New-AdvisorToolResult -Name $Name -Ok $true -Proposal $proposal -Data ([ordered]@{
                        proposal_id = $proposal.ProposalId
                        status      = 'Vorschlag wird dem Benutzer angezeigt. Nichts wurde ausgeführt; der Benutzer entscheidet selbst.'
                    })
            }
        }
    }
    catch {
        & $fail "Fehler bei $($Name): $($_.Exception.Message)"
    }
}
