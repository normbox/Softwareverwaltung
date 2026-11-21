function Remove-AppData {
    <#
    .SYNOPSIS
        Entfernt alle Daten, die die App für diesen Benutzer angelegt hat. Mit -WhatIf nur der Plan.
    .DESCRIPTION
        Reihenfolge: zuerst der Admin-Ordner Program Files\Softwareverwaltung (nur die Unterordner Helper und
        RegistryBackup, den Ordner selbst nur, wenn er danach leer ist; eine UAC-Abfrage; HKLM-Sicherungen aller
        Benutzer; entfällt mit -SkipMachine), dann gespeicherte Schlüssel (Anmeldeinformationsverwaltung, SoftwareInventory/<Dienst>), Reste im
        Temp-Ordner (nur die festen Namen der App), %LOCALAPPDATA%\SoftwareInventory (Logs, Aktionsprotokoll,
        Zwischenspeicher, Scans, Registry-Sicherungen des Benutzers), %APPDATA%\SoftwareInventory (Einstellungen,
        bestätigte CPE-Zuordnungen, Einstellungen der App).

        Sicherheit: Gelöscht wird nur innerhalb dieser Orte und nur auf einem lokalen Laufwerk (sonst
        AppDataRootInvalid). Das Durchlaufen folgt keinem Link: Junctions und symbolische Links werden als Link
        entfernt, ihr Ziel bleibt. Ist ein App-Ordner selbst ein Link, bleibt er stehen (AppDataRootIsLink).
        Gesperrte Dateien werden übersprungen, der Rest wird trotzdem entfernt (PartlyRemoved).

        Wird die UAC-Abfrage abgelehnt, bleibt der Admin-Ordner (AppDataMachineDenied), alles andere wird entfernt.

        Nicht entfernt: Umgebungsvariablen mit Schlüsseln, Wiederherstellungspunkte und die Daten anderer Benutzer.

        Danach schreiben Fehlerprotokoll, Hinweise, Zwischenspeicher und Bereinigung in dieser Sitzung still nichts mehr;
        Aktionen, Einstellungen, CPE-Zuordnungen, Scans und Registry-Sicherungen brechen mit AppDataAlreadyRemoved ab
        (keine Aktion ohne Protokoll). Das Ergebnis wird nur zurückgegeben, nicht protokolliert (das Aktionsprotokoll ist
        mit gelöscht). Registry-Sicherungen sind danach nicht mehr wiederherstellbar.
    .OUTPUTS
        SoftwareInventory.AppDataRemoval: Result (Removed, PartlyRemoved, NotPresent), Message und Items (je Ort Kind,
        Path, Result, RemovedCount, FailedCount, FirstFailedPath, Message, Problems). Mit -WhatIf der Plan aus
        Get-AppDataRemovalPlan.
    .EXAMPLE
        Remove-AppData -WhatIf
    .EXAMPLE
        Remove-AppData -Confirm:$false
    .EXAMPLE
        Remove-AppData -SkipMachine -Confirm:$false
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.AppDataRemoval', 'SoftwareInventory.AppDataRemovalPlan')]
    param(
        # Nur die Daten dieses Benutzers; Program Files\Softwareverwaltung bleibt, es gibt nie eine UAC-Abfrage.
        [switch] $SkipMachine
    )

    $variables = @{ Roaming = '%APPDATA%'; Local = '%LOCALAPPDATA%' }
    $locations = @(Get-AppDataLocation)
    $kinds = if ($SkipMachine) { 'Roaming', 'Local' } else { 'Roaming', 'Local', 'Machine' }
    $target = @($locations | Where-Object Kind -In $kinds | ForEach-Object { if ($_.Path) { $_.Path } else { $variables[$_.Kind] } }) -join ', '
    $action = if ($SkipMachine) { 'AppDataRemoveAction' } else { 'AppDataRemoveActionMachine' }
    if (-not $PSCmdlet.ShouldProcess($target, (Get-LocalizedString $action))) {
        return (Get-AppDataRemovalPlan)
    }

    # Ab hier nichts mehr schreiben, auch nicht ins Fehlerprotokoll, sonst entstünden die Ordner neu.
    $script:AppDataRemoved = $true
    $items = [System.Collections.Generic.List[object]]::new()
    # Admin-Teil zuerst: Die UAC-Abfrage kommt, solange noch alles da ist; abgelehnt geht der Rest trotzdem weiter.
    if (-not $SkipMachine) { $items.Add((Remove-AppMachineData)) }
    $items.Add((Remove-AppStoredCredential))
    $items.Add((Remove-AppTempFile))
    foreach ($kind in 'Local', 'Roaming') {
        $location = $locations | Where-Object Kind -EQ $kind
        if ($location.Problem) {
            $item = New-AppDataRemovalItem -Kind $kind -Path $variables[$kind]
            $item.Problems.Add($location.Problem)
            $items.Add((Complete-AppDataRemovalItem $item 'Skipped'))
        }
        else { $items.Add((Remove-AppDataFolder -Kind $kind -Path $location.Path)) }
    }

    $results = @($items | ForEach-Object Result)
    $result = if ($results -contains 'PartlyRemoved' -or $results -contains 'Skipped') { 'PartlyRemoved' }
    elseif ($results -contains 'Removed') { 'Removed' }
    else { 'NotPresent' }
    $code = @{ Removed = 'AppDataRemovalDone'; PartlyRemoved = 'AppDataRemovalPartial'; NotPresent = 'AppDataRemovalNothing' }[$result]
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.AppDataRemoval'
        Result     = $result
        Message    = New-InventoryMessage $code
        Items      = @($items)
    }
}
