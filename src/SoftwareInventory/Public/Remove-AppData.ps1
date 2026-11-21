function Remove-AppData {
    <#
    .SYNOPSIS
        Entfernt alle Daten, die die App für diesen Benutzer angelegt hat. Mit -WhatIf nur der Plan.
    .DESCRIPTION
        Reihenfolge: gespeicherte Schlüssel (Anmeldeinformationsverwaltung, SoftwareInventory/<Dienst>), Reste im
        Temp-Ordner (nur die festen Namen der App), %LOCALAPPDATA%\SoftwareInventory (Logs, Aktionsprotokoll,
        Zwischenspeicher, Scans, Registry-Sicherungen des Benutzers), %APPDATA%\SoftwareInventory (Einstellungen,
        bestätigte CPE-Zuordnungen, Einstellungen der App).

        Sicherheit: Gelöscht wird nur innerhalb dieser Orte und nur auf einem lokalen Laufwerk (sonst
        AppDataRootInvalid). Das Durchlaufen folgt keinem Link: Junctions und symbolische Links werden als Link
        entfernt, ihr Ziel bleibt. Ist ein App-Ordner selbst ein Link, bleibt er stehen (AppDataRootIsLink).
        Gesperrte Dateien werden übersprungen, der Rest wird trotzdem entfernt (PartlyRemoved).

        Nicht entfernt: Program Files\Softwareverwaltung (Helfer-Kopie, HKLM-Sicherungen; braucht Administratorrechte),
        Umgebungsvariablen mit Schlüsseln, Wiederherstellungspunkte und die Daten anderer Benutzer.

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
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.AppDataRemoval', 'SoftwareInventory.AppDataRemovalPlan')]
    param()

    $variables = @{ Roaming = '%APPDATA%'; Local = '%LOCALAPPDATA%' }
    $locations = @(Get-AppDataLocation)
    if (-not $PSCmdlet.ShouldProcess((@($locations | Where-Object Kind -In 'Roaming', 'Local' | ForEach-Object { if ($_.Path) { $_.Path } else { $variables[$_.Kind] } }) -join ', '), (Get-LocalizedString 'AppDataRemoveAction'))) {
        return (Get-AppDataRemovalPlan)
    }

    # Ab hier nichts mehr schreiben, auch nicht ins Fehlerprotokoll, sonst entstünden die Ordner neu.
    $script:AppDataRemoved = $true
    $items = [System.Collections.Generic.List[object]]::new()
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
