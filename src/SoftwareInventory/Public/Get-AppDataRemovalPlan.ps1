function Get-AppDataRemovalPlan {
    <#
    .SYNOPSIS
        Zeigt, welche Daten die App angelegt hat und was „Alle App-Daten entfernen“ löschen würde. Ändert nichts.
    .DESCRIPTION
        Locations: je Ort (Roaming, Local, Temp, Machine) Pfad, Zustand (Present, Missing, RootIsLink, NotFolder,
        Invalid), Größe, Anzahl Dateien und Links sowie Problems (Meldungen mit Code). Gezählt wird ohne Links zu
        folgen: Ein Link zählt als ein Eintrag, sein Ziel nicht. Temp umfasst nur Reste mit den festen Namen der App.
        Machine ist Program Files\Softwareverwaltung (Helfer-Kopie und HKLM-Sicherungen aller Benutzer); Remove-AppData
        entfernt davon nur die Unterordner Helper und RegistryBackup, mit einer UAC-Abfrage. RequiresElevation sagt, ob
        beim Entfernen eine UAC-Abfrage kommt (ein Unterordner ist da und die Prüfung ohne Adminrechte hat nichts
        gefunden), HelperCopyPresent, ob die Helfer-Kopie als echter Ordner da ist.
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
    # Admin-Teil: dieselbe Prüfung wie beim Entfernen. Gibt es ein Problem, kommt beim Entfernen keine UAC-Abfrage.
    $machine = $locations | Where-Object Kind -EQ 'Machine'
    $check = Get-AppMachineRemovalCheck
    # Ein Link als Ordner steht schon aus Get-AppDataFolderState in Problems; doppelte Meldungen fallen weg.
    $machine.Problems = @(@($machine.Problems) + @($check.Problems) | Where-Object { $_ } | Sort-Object -Property Text -Unique)
    $helperPath = [System.IO.Path]::Combine($check.Root, $script:AppMachineSubfolders[0])

    [pscustomobject] [ordered]@{
        PSTypeName         = 'SoftwareInventory.AppDataRemovalPlan'
        Locations          = @($locations)
        TotalSize          = $total
        UserBackupCount    = @($backups | Where-Object BackupScope -EQ 'User').Count
        MachineBackupCount = @($backups | Where-Object BackupScope -EQ 'Machine').Count
        CpeMappingCount    = [int] $cpeCount
        StoredCredentials  = @(Get-AppStoredCredential)
        TempFiles          = @($tempFiles | ForEach-Object Name)
        RequiresElevation  = [bool] ($check.Present.Count -and -not $check.Problems.Count)
        HelperCopyPresent  = $check.Present -contains $helperPath
    }
}
