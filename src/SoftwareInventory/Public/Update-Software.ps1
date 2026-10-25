function Update-Software {
    <#
    .SYNOPSIS
        Aktualisiert Programme über winget; ohne winget-Paket nur mit Herstellerlink.
    .DESCRIPTION
        Liest den aktuellen Zustand neu (Registry, Store-Apps, winget), statt dem übergebenen
        Datensatz zu vertrauen. Aktualisiert wird nur über winget mit exakter ID und Quelle aus
        dem Scan (winget upgrade --id <Id> --exact --source <Quelle>). Ohne winget-Paket wird nichts
        heruntergeladen; Result ist dann ManualUpdateRequired und VendorUrl nennt den Herstellerlink.

        Administratorrechte werden nur für die einzelne Aktion angefordert (UAC) und nur, wenn das
        Programm für den ganzen Rechner installiert ist. Programme des Benutzers (HKCU) laufen ohne
        Adminrechte. Ist der Bereich unbekannt, fordert winget die UAC bei Bedarf selbst an.

        Erfolg heißt: Exit-Code passt UND die Version ist danach höher. Jede Aktion wird protokolliert
        (Get-ActionLog). -WhatIf führt nichts aus und liefert ein Ergebnis mit Result „Planned“ samt
        genauem Befehl (CommandLine). Schlägt eine Aktion fehl, wird kein anderer Weg automatisch versucht.
    .PARAMETER InputObject
        Datensätze aus Get-SoftwareInventory, Get-InventorySnapshot oder Objekte mit .Record
        (Get-SecurityRating, Test-SoftwareUpdate).
    .PARAMETER CreateRestorePoint
        Vorher einen Wiederherstellungspunkt anlegen. Ohne Angabe gilt die Einstellung
        (Set-InventorySetting -Enable RestorePoint; standardmäßig aus). Windows legt höchstens einen
        Punkt pro 24 Stunden an; das Ergebnis meldet Created, Skipped, NotAvailable oder Failed.
        Ein fehlgeschlagener Wiederherstellungspunkt bricht die Aktion nicht ab.
    .PARAMETER TimeoutMinutes
        Höchstens so lange auf das Ende warten (Standard 60). Danach Result „Timeout“; das Programm
        wird nicht beendet.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object AvailableVersion | Update-Software -WhatIf
    .EXAMPLE
        Get-SecurityRating -InputObject (Get-SoftwareInventory) | Where-Object Rating -eq Red | Update-Software
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject,

        [switch] $CreateRestorePoint,

        [ValidateRange(1, 1440)]
        [int] $TimeoutMinutes = 60
    )

    begin {
        $restorePoint = if ($PSBoundParameters.ContainsKey('CreateRestorePoint')) { $CreateRestorePoint.IsPresent } else { [bool] (Read-InventorySetting).Actions.RestorePoint }
    }
    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            $prepared = Resolve-SoftwareAction -Action Update -InputObject $item -RestorePoint $restorePoint
            if (-not $prepared) { continue }
            if ($prepared.Result) { $prepared.Result; continue }
            if ($PSCmdlet.ShouldProcess($prepared.Plan.Name, $prepared.Description)) {
                Invoke-ActionPlan -Plan $prepared.Plan -Record $prepared.Record -TimeoutMinutes $TimeoutMinutes
            }
            else {
                New-DeclinedActionResult $prepared
            }
        }
    }
}
