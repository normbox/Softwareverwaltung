function Uninstall-Software {
    <#
    .SYNOPSIS
        Deinstalliert Programme: über winget, sonst MSI, Store-App oder Registry-Befehl.
    .DESCRIPTION
        Liest den aktuellen Zustand neu (Registry, Store-Apps, winget), statt dem übergebenen
        Datensatz zu vertrauen. Methoden in dieser Reihenfolge (-Method Auto):
          1. winget uninstall --id <Id> --exact --source <Quelle>
          2. msiexec /x {ProductCode} /qn /norestart /l*v <Log>
          3. Remove-AppxPackage (Store-Apps, immer im aktuellen Benutzer)
          4. QuietUninstallString, 5. UninstallString aus der Registry
        Registry-Befehle werden ohne Shell gestartet; Skript-Interpreter (cmd, powershell, …) werden
        abgelehnt. Ein Befehl aus HKCU läuft nie mit Adminrechten, und mit Adminrechten wird keine
        Datei gestartet, die der Benutzer verändern könnte.

        Administratorrechte nur für Programme des ganzen Rechners (HKLM), per UAC für diese eine
        Aktion. Erfolg heißt: Exit-Code passt UND der Eintrag ist danach verschwunden. Schlägt die
        gewählte Methode fehl, wird keine andere automatisch versucht; NextMethod nennt die nächste.
        Jede Aktion wird protokolliert (Get-ActionLog). -WhatIf führt nichts aus und liefert ein
        Ergebnis mit Result „Planned“ samt genauem Befehl (CommandLine).
    .PARAMETER InputObject
        Datensätze aus Get-SoftwareInventory, Get-InventorySnapshot oder Objekte mit .Record.
    .PARAMETER Method
        Auto (Standard) oder eine bestimmte Methode: Winget, Msi, Appx, QuietUninstallString, UninstallString.
    .PARAMETER CreateRestorePoint
        Vorher einen Wiederherstellungspunkt anlegen; ohne Angabe gilt die Einstellung
        (Set-InventorySetting -Enable RestorePoint; standardmäßig aus).
    .PARAMETER ConfirmedCommandLine
        CommandLine aus dem -WhatIf-Ergebnis, das der Benutzer bestätigt hat. Ergibt die erneute
        Prüfung einen anderen Befehl, wird nichts ausgeführt (Result Cancelled, Message nennt den neuen Befehl).
        Für Oberflächen, die zwischen Bestätigen und Ausführen Zeit vergehen lassen.
    .PARAMETER TimeoutMinutes
        Höchstens so lange auf das Ende warten (Standard 60). Danach Result „Timeout“.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object Name -like 'Contoso*' | Uninstall-Software -WhatIf
    .EXAMPLE
        $r = Get-SoftwareInventory | Where-Object Name -eq 'Contoso Tool' | Uninstall-Software -Confirm:$false
        if ($r.Result -eq 'Failed' -and $r.NextMethod) { $r | Format-List Message, NextMethod }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject,

        [ValidateSet('Auto', 'Winget', 'Msi', 'Appx', 'QuietUninstallString', 'UninstallString')]
        [string] $Method = 'Auto',

        [switch] $CreateRestorePoint,

        [ValidateRange(1, 1440)]
        [int] $TimeoutMinutes = 60,

        [string] $ConfirmedCommandLine
    )

    begin {
        $restorePoint = if ($PSBoundParameters.ContainsKey('CreateRestorePoint')) { $CreateRestorePoint.IsPresent } else { [bool] (Read-InventorySetting).Actions.RestorePoint }
    }
    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            $prepared = Resolve-SoftwareAction -Action Uninstall -InputObject $item -Method $Method -RestorePoint $restorePoint -ConfirmedCommandLine $ConfirmedCommandLine
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
