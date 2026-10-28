function Resolve-InstallLocation {
    <#
    .SYNOPSIS
        Ermittelt den Installationsordner eines Programms und nennt, woher die Angabe stammt.
    .DESCRIPTION
        Quellen der Reihe nach:
          1. InstallLocation aus dem Installer-Eintrag (bei Store-Apps aus dem App-Paket) – sicher
          2. Ordner der gefundenen Programmdatei (portable Programme) – sicher
          3. Ordner aus DisplayIcon (Programmsymbol) – vermutlich
          4. Ordner aus dem Deinstallationsbefehl, nur wenn er ein eigenes Deinstallationsprogramm
             startet (unins*, uninstall*, setup*), nicht msiexec und keine fremden Starter wie Steam – vermutlich
          5. bei MSI der gemeinsame Ordner der .exe-Komponenten – vermutlich
        Abgeleitete Ordner zählen nur, wenn dort ein Programm (.exe, kein Deinstallationsprogramm)
        liegt; Zwischenspeicher des Installers (Windows\Installer, AppData\…\Installer, Package Cache,
        Temp) nie. Ohne Ergebnis ist Path leer und Reason nennt den Grund als Meldung mit Code:
        LocationNotFound (Ordner aus dem Installer-Eintrag fehlt), LocationOnlyInstallerCache,
        LocationNoProgramExe oder LocationNoData.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object Name -like '7-Zip*' | Resolve-InstallLocation
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.InstallLocation')]
    param(
        # Datensatz aus Get-SoftwareInventory/Get-PortableSoftware oder Ergebnis von Get-SecurityRating
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject
    )

    process {
        $record = Get-ActionRecord $InputObject
        if (-not $record -or -not $record.PSObject.Properties['Name']) {
            Write-Error (Get-LocalizedString 'ErrorNotInventoryRecord')
            return
        }
        $missing = $null
        $cacheOnly = $false
        $noExe = $null

        # 1. Installer-Eintrag bzw. App-Paket: sicher, muss aber existieren
        $location = Get-RecordValue $record 'InstallLocation'
        if ($location) {
            $location = [Environment]::ExpandEnvironmentVariables($location.Trim('"', ' '))
            $source = if (Get-RecordValue $record 'PackageFullName') { 'AppPackage' } else { 'InstallerEntry' }
            if ([System.IO.Directory]::Exists($location)) { return New-InstallLocationResult $record $location $source $true $null }
            $missing = $location
        }

        # 2. Portable Programme: Ordner der gefundenen Datei
        $file = Get-RecordValue $record 'FilePath'
        if ($file -and [System.IO.File]::Exists($file)) {
            return New-InstallLocationResult $record ([System.IO.Path]::GetDirectoryName($file)) 'FileSearch' $true $null
        }

        # 3.–5. Abgeleitete Ordner
        $candidates = [System.Collections.Generic.List[object]]::new()
        $icon = Get-RecordValue $record 'DisplayIcon'
        if ($icon -and [System.IO.Path]::IsPathRooted($icon)) { $candidates.Add(@{ Source = 'DisplayIcon'; Folder = [System.IO.Path]::GetDirectoryName($icon) }) }
        $uninstall = Get-RecordValue $record 'UninstallString'
        if ($uninstall) {
            $parts = Split-CommandLine $uninstall
            $name = if ($parts.FilePath) { [System.IO.Path]::GetFileName($parts.FilePath) }
            # Nur ein eigenes Deinstallationsprogramm verrät den Ordner; Starter anderer Programme (Steam,
            # Overwolf, Chrome) liegen im Ordner des Starters, nicht des Programms.
            if ($name -and $name -match $script:UninstallerPattern -and [System.IO.Path]::IsPathRooted($parts.FilePath)) {
                $candidates.Add(@{ Source = 'UninstallCommand'; Folder = [System.IO.Path]::GetDirectoryName($parts.FilePath) })
            }
        }
        foreach ($c in $candidates) {
            if (Test-InstallerCachePath $c.Folder) { $cacheOnly = $true; continue }
            if (Test-ProgramFolder $c.Folder) { return New-InstallLocationResult $record $c.Folder $c.Source $false $null }
            if (-not $noExe -and [System.IO.Directory]::Exists($c.Folder)) { $noExe = $c.Folder }
        }

        $code = Get-RecordValue $record 'ProductCode'
        if ($code) {
            try {
                $folder = Get-MsiProgramFolder -ProductCode $code
                if ($folder -and (Test-InstallerCachePath $folder)) { $cacheOnly = $true }
                elseif ($folder -and (Test-ProgramFolder $folder)) {
                    return New-InstallLocationResult $record $folder 'MsiComponents' $false $null
                }
            }
            catch { Write-Verbose "MSI-Komponenten nicht lesbar ($code): $($_.Exception.Message)" }
        }

        # Kein Ordner: Grund in fester Reihenfolge
        $reason = if ($missing) { New-InventoryMessage LocationNotFound $missing }
        elseif ($noExe) { New-InventoryMessage LocationNoProgramExe $noExe }
        elseif ($cacheOnly) { New-InventoryMessage LocationOnlyInstallerCache }
        else { New-InventoryMessage LocationNoData }
        New-InstallLocationResult $record $null $null $false $reason
    }
}
