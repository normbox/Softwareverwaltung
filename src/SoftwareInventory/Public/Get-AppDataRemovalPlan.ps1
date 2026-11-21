function Get-AppDataRemovalPlan {
    <#
    .SYNOPSIS
        Zeigt, welche Daten die App angelegt hat und was „Alle App-Daten entfernen“ löschen würde. Ändert nichts.
    .DESCRIPTION
        Locations: je Ort (Roaming, Local, Temp, Machine) Pfad, Zustand (Present, Missing, RootIsLink, NotFolder,
        Invalid), Größe, Anzahl Dateien und Links sowie Problems (Meldungen mit Code). Gezählt wird ohne Links zu
        folgen: Ein Link zählt als ein Eintrag, sein Ziel nicht. Temp umfasst nur Reste mit den festen Namen der App.
        Machine (Program Files\Softwareverwaltung: Helfer-Kopie und HKLM-Sicherungen aller Benutzer) wird nur
        angezeigt; Remove-AppData entfernt ihn nicht (dafür braucht es Administratorrechte).
        Dazu: UserBackupCount und MachineBackupCount (Registry-Sicherungen), CpeMappingCount (bestätigte
        CPE-Zuordnungen in cpe-map.json), StoredCredentials (Dienste mit gespeichertem Schlüssel; nie der Schlüssel)
        und TempFiles (Dateinamen). Daten anderer Benutzer liegen in deren Profil und werden nicht gezählt.
    .EXAMPLE
        Get-AppDataRemovalPlan
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AppDataRemovalPlan')]
    param()

    $tempFiles = @()
    $locations = foreach ($location in Get-AppDataLocation) {
        $entry = [pscustomobject] [ordered]@{
            PSTypeName = 'SoftwareInventory.AppDataLocation'
            Kind       = $location.Kind
            Path       = $location.Path
            State      = 'Missing'
            Size       = [long] 0
            FileCount  = 0
            LinkCount  = 0
            Problems   = @()
        }
        if ($location.Problem) {
            $entry.State = 'Invalid'
            $entry.Problems = @($location.Problem)
        }
        elseif ($location.Kind -eq 'Temp') {
            $tempFiles = @(Get-AppTempFile)
            if ($tempFiles.Count) { $entry.State = 'Present' }
            $entry.FileCount = $tempFiles.Count
            foreach ($file in $tempFiles) { $entry.Size += $file.Length }
        }
        else {
            $entry.State = Get-AppDataFolderState -Path $location.Path
            switch ($entry.State) {
                'Present' {
                    $measure = Measure-AppDataFolder -Path $location.Path
                    $entry.Size = $measure.Size
                    $entry.FileCount = $measure.FileCount
                    $entry.LinkCount = $measure.LinkCount
                    $entry.Problems = @($measure.Unreadable | ForEach-Object { New-InventoryMessage AppDataUnreadable $_ })
                }
                'RootIsLink' { $entry.Problems = @(New-InventoryMessage AppDataRootIsLink $location.Path) }
                'NotFolder' { $entry.Problems = @(New-InventoryMessage AppDataRootNotFolder $location.Path) }
            }
        }
        $entry
    }

    # Ohne gültigen App-Ordner lässt sich nichts zählen; der Ort steht dann mit Invalid in Locations.
    $backups = try { @(Get-RegistryBackupFile) } catch { @() }
    $cpeCount = try { (Read-CpeMapping 3>$null).Count } catch { 0 }
    $total = [long] 0
    foreach ($location in $locations) { $total += $location.Size }

    [pscustomobject] [ordered]@{
        PSTypeName         = 'SoftwareInventory.AppDataRemovalPlan'
        Locations          = @($locations)
        TotalSize          = $total
        UserBackupCount    = @($backups | Where-Object BackupScope -EQ 'User').Count
        MachineBackupCount = @($backups | Where-Object BackupScope -EQ 'Machine').Count
        CpeMappingCount    = [int] $cpeCount
        StoredCredentials  = @(Get-AppStoredCredential)
        TempFiles          = @($tempFiles | ForEach-Object Name)
    }
}
