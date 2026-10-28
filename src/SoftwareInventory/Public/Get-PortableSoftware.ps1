function Get-PortableSoftware {
    <#
    .SYNOPSIS
        Findet Programme, die in keiner Installationsliste stehen (portable oder herumliegende .exe).
    .DESCRIPTION
        Wertet die aktivierten Nutzungsspuren aus (UserAssist, laufende Prozesse, Autostart,
        geplante Aufgaben) und durchsucht die aktivierten Ordner und Laufwerke nach .exe-Dateien.
        Ohne Parameter gelten die Einstellungen (Set-InventorySetting); standardmäßig ist nichts
        aktiviert. Dann gelten die Unterschalter Nutzungsspuren (TraceSearch) und Dateisuche
        (FileSearch), und von Ordnern und Laufwerken zählt nur die Liste der gewählten Option
        (FileScan.Mode: Folders oder Drives). Mit Parametern gilt nur, was angegeben ist.
        Nicht verbundene Laufwerke und fehlende Ordner werden mit Hinweis (Warnung) übersprungen.
        Nutzungsspuren auf nicht erreichbare Pfade (z. B. abgezogener USB-Stick) erscheinen als
        Datensatz mit Flag PathUnreachable, statt verworfen zu werden.
        Dateien in Windows-Ordnern und in den Ordnern installierter Programme werden ausgelassen.
        Die Dateien werden nicht ausgeführt; gelesen werden Versionsinfo, Signatur und optional SHA256.
        Aus Temp-Ordnern meldet der Dateiscan nur unsignierte oder ungültig signierte Dateien;
        mit Nutzungsspur wird jede Datei gemeldet.
        Identische Kopien werden zu einem Datensatz zusammengefasst (CopyPaths).
        Benötigt keine Administratorrechte.
    .PARAMETER Trace
        Auszuwertende Nutzungsspuren: UserAssist, Process, Autostart, ScheduledTask.
    .PARAMETER Path
        Ordner für den Dateiscan; Umgebungsvariablen wie %USERPROFILE% erlaubt.
    .PARAMETER Drive
        Laufwerke für den Dateiscan, z. B. C, D (siehe Get-ScanDrive).
    .PARAMETER IncludeTemp
        Temp-Ordner mit durchsuchen (sonst ausgelassen).
    .PARAMETER ComputeHash
        SHA256 berechnen (liest jede Datei vollständig, kostet Zeit).
    .PARAMETER ExcludePath
        Eigene Ordner, die nie betreten werden (Dateiscan und Spuren). Ohne Angabe gilt
        FileScan.ExcludePaths aus den Einstellungen – auch wenn andere Parameter angegeben sind.
    .PARAMETER NoSmartExclusion
        Schaltet Herstellerordner-Regel und Abgleich über Name/Version ab (mehr Treffer).
        Ohne Angabe gilt FileScan.SmartExclusions aus den Einstellungen (Standard: an).
    .PARAMETER Inventory
        Installierte Programme, deren Ordner ausgelassen werden. Standard: Get-SoftwareInventory
        mit den aktivierten Quellen.
    .EXAMPLE
        Set-InventorySetting -Preset Quick
        Get-PortableSoftware | Format-Table Name, Version, Flags, FilePath
    .EXAMPLE
        Get-PortableSoftware -Drive D, E -ComputeHash -NoSmartExclusion
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [ValidateSet('UserAssist', 'Process', 'Autostart', 'ScheduledTask')]
        [string[]] $Trace = @(),

        [string[]] $Path = @(),

        [string[]] $Drive = @(),

        [switch] $IncludeTemp,

        [switch] $ComputeHash,

        [string[]] $ExcludePath = @(),

        [switch] $NoSmartExclusion,

        [object[]] $Inventory
    )

    $setting = Read-InventorySetting
    # Eigene Ausschlüsse und SmartExclusions gelten aus den Einstellungen, solange sie nicht als Parameter kommen.
    if (-not $PSBoundParameters.ContainsKey('ExcludePath')) { $ExcludePath = @($setting.FileScan.ExcludePaths) }
    $smart = if ($PSBoundParameters.ContainsKey('NoSmartExclusion')) { -not $NoSmartExclusion } else { [bool] $setting.FileScan.SmartExclusions }
    $userExclusions = @($ExcludePath | Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })

    $explicit = 'Trace', 'Path', 'Drive', 'IncludeTemp', 'ComputeHash' | Where-Object { $PSBoundParameters.ContainsKey($_) }
    if (-not $explicit) {
        # Unterschalter Nutzungsspuren/Dateisuche und nur die Liste der gewählten Option „Wo suchen“
        $plan = Get-PortableSearchPlan $setting
        $Trace = @($plan.Trace)
        $Path = @($plan.Path)
        $Drive = @($plan.Drive)
        $IncludeTemp = [switch] $setting.FileScan.IncludeTemp
        $ComputeHash = [switch] $setting.FileScan.ComputeHash
    }
    $Path = @($Path | Where-Object { $_ } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_) })
    if (-not $Trace -and -not $Path -and -not $Drive) {
        Write-Warning 'Keine Nutzungsspuren und keine Scan-Ordner aktiviert. Aktivieren mit Set-InventorySetting, z. B. -Preset Quick.'
        return
    }

    if (-not $PSBoundParameters.ContainsKey('Inventory')) {
        $Inventory = @(Get-SoftwareInventory -WarningAction SilentlyContinue)
        if (-not $Inventory) {
            Write-Warning 'Keine Inventar-Quelle aktiviert: Installierte Programme können nicht ausgelassen werden und erscheinen mit.'
        }
    }
    $exclusions = @(Get-ScanExclusion -Inventory $Inventory) + $userExclusions
    $tempDirs = @(Get-TempDirectory)
    $writableWindowsDirs = @(Get-WritableWindowsDirectory)
    $publishers = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($record in $Inventory) {
        $key = Get-PublisherKey $record.Publisher
        if ($key) { [void] $publishers.Add($key) }
    }
    $scanExclusions = if ($IncludeTemp) { $exclusions } else { @($exclusions) + @($tempDirs) }

    # Nicht verbundene Laufwerke und fehlende Ordner: überspringen, mit Hinweis statt Fehler.
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($d in $Drive) {
        $root = ConvertTo-DriveRoot $d
        if (Test-ScanRoot $root) { $roots.Add($root) }
        else { Write-Warning (Get-LocalizedString 'PortableDriveNotConnected' @($root.TrimEnd('\'))) }
    }
    foreach ($p in $Path) {
        if (Test-ScanRoot $p) { $roots.Add($p) }
        else { Write-Warning (Get-LocalizedString 'PortableFolderNotFound' @($p)) }
    }
    # Spuren auf Pfade, deren Laufwerk gerade fehlt (z. B. abgezogener USB-Stick): als Treffer behalten.
    $unreachable = @{}

    # Kandidaten: Pfad -> gesammelte Hinweise
    $candidates = @{}
    $addCandidate = {
        param($File, $Evidence, $LastRun, $RunCount)
        $key = $File.ToLowerInvariant()
        if (-not $candidates.ContainsKey($key)) {
            $candidates[$key] = @{ Path = $File; Evidence = [System.Collections.Generic.HashSet[string]]::new(); LastRun = $null; RunCount = $null }
        }
        $c = $candidates[$key]
        [void] $c.Evidence.Add($Evidence)
        if ($LastRun -and (-not $c.LastRun -or $LastRun -gt $c.LastRun)) { $c.LastRun = $LastRun }
        if ($RunCount) { $c.RunCount = $RunCount }
    }

    foreach ($source in $Trace | ForEach-Object { "Get-${_}Trace" }) {
        try {
            foreach ($hint in & $source) {
                if (-not (Test-Path -LiteralPath $hint.Path -PathType Leaf)) {
                    # Datei weg, Laufwerk da: Programm entfernt, Spur veraltet. Laufwerk weg: Treffer „nicht erreichbar“.
                    if (-not (Test-PathRootReachable $hint.Path) -and -not (Test-PathExcluded -Path $hint.Path -Exclusion $userExclusions)) {
                        $key = $hint.Path.ToLowerInvariant()
                        if (-not $unreachable.ContainsKey($key)) {
                            $unreachable[$key] = @{ Path = $hint.Path; Evidence = [System.Collections.Generic.HashSet[string]]::new(); LastRun = $null; RunCount = $null }
                        }
                        $u = $unreachable[$key]
                        [void] $u.Evidence.Add($hint.Evidence)
                        if ($hint.LastRun -and (-not $u.LastRun -or $hint.LastRun -gt $u.LastRun)) { $u.LastRun = $hint.LastRun }
                        if ($hint.RunCount) { $u.RunCount = $hint.RunCount }
                    }
                    continue
                }
                if (Test-PathExcluded -Path $hint.Path -Exclusion $userExclusions) { continue }
                # Läuft oder startet etwas aus einem für Benutzer beschreibbaren Windows-Unterordner,
                # wird es immer gemeldet – der Windows-Ordner ist sonst ausgeschlossen.
                $fromWritableWindows = $hint.Evidence -in 'Process', 'Autostart', 'ScheduledTask' -and
                    (Test-PathExcluded -Path $hint.Path -Exclusion $writableWindowsDirs)
                if (-not $fromWritableWindows -and (Test-PathExcluded -Path $hint.Path -Exclusion $exclusions)) { continue }
                & $addCandidate $hint.Path $hint.Evidence $hint.LastRun $hint.RunCount
            }
        }
        catch {
            Write-Warning "Spurenquelle $source nicht lesbar: $_"
        }
    }

    $files = if ($roots.Count) { Find-ExecutableFile -Root $roots -ExcludeDirectory $scanExclusions } else { @() }
    foreach ($file in $files) {
        & $addCandidate $file 'FileScan' $null $null
    }

    $infos = [System.Collections.Generic.List[object]]::new()
    $vendorDirs = [System.Collections.Generic.List[string]]::new()
    $i = 0
    # Sortiert, damit Gleichstände (gleiche Größe, gleiche Pfadlänge) immer gleich aufgelöst werden.
    foreach ($c in $candidates.Keys | Sort-Object | ForEach-Object { $candidates[$_] }) {
        $i++
        Write-Progress -Activity (Get-LocalizedString 'ProgressCheckFiles') -Status $c.Path -PercentComplete ($i * 100 / $candidates.Count) -Id 2
        try {
            $info = Get-ExecutableInfo -Path $c.Path -SkipHash:(-not $ComputeHash)
        }
        catch {
            Write-Verbose "Nicht lesbar: $($c.Path)"
            continue
        }
        # Signierte Dateien in Temp sind meist Installer-Reste. Verworfen werden sie nur, wenn allein
        # der Dateiscan sie fand; läuft oder startet etwas aus Temp, wird es immer gemeldet.
        $onlyFileScan = $c.Evidence.Count -eq 1 -and $c.Evidence.Contains('FileScan')
        if ($onlyFileScan -and $info.SignatureStatus -eq 'Valid' -and (Test-PathExcluded -Path $info.Path -Exclusion $tempDirs)) { continue }
        if ($smart -and (Test-InstalledProgramFile -Info $info -InstalledPublisher $publishers)) {
            $vendorDirs.Add((Get-VendorDirectory $info.Path))
            continue
        }
        $info | Add-Member -Force -NotePropertyMembers @{ Evidence = [string[]] @($c.Evidence); LastRun = $c.LastRun; RunCount = $c.RunCount }
        $infos.Add($info)
    }
    Write-Progress -Activity (Get-LocalizedString 'ProgressCheckFiles') -Id 2 -Completed

    # Herstellerordner mit nachweislich installierten Dateien gehören ganz zur Installation
    # (z. B. unsignierte Hilfsprogramme ohne Versionsinfo).
    $vendorDirs = @($vendorDirs | Select-Object -Unique)
    $infos = @($infos | Where-Object { -not (Test-PathExcluded -Path $_.Path -Exclusion $vendorDirs) })
    if ($smart) { $infos = @(Remove-InstalledMatch -Info $infos -Inventory $Inventory -ScanRoot $roots) }
    $records = foreach ($group in $infos | Group-Object { "$($_.Directory)|$(Get-ExecutableProductName $_)".ToLowerInvariant() }) {
        ConvertTo-PortableRecord -File $group.Group
    }
    $records = @(Merge-NestedComponent -Record $records -ScanRoot $roots)
    $records = @(Merge-PortableCopy -Record $records)
    Add-MultipleVersionFlag -Record $records
    $records += @($unreachable.Values | ForEach-Object { New-UnreachableRecord $_ })
    $records | Sort-Object Name, FilePath
}

function Test-ScanRoot {
    # Ist ein Laufwerk oder Ordner für die Dateisuche gerade vorhanden?
    param([string] $Path)
    Test-Path -LiteralPath $Path -PathType Container
}

function Test-PathRootReachable {
    # Ist das Laufwerk (bzw. die Freigabe) eines Pfads gerade erreichbar? Relative Pfade gelten als erreichbar.
    param([string] $Path)
    $root = try { [System.IO.Path]::GetPathRoot($Path) } catch { $null }
    if (-not $root) { return $true }
    Test-Path -LiteralPath $root -PathType Container
}

function New-UnreachableRecord {
    # Treffer aus Nutzungsspuren, dessen Laufwerk gerade fehlt: nichts lesbar außer Pfad und Spur.
    param($Candidate)
    $evidence = [string[]] @($Candidate.Evidence | Sort-Object)
    $flags = [System.Collections.Generic.List[string]]::new()
    $flags.Add('PathUnreachable')
    if ($evidence -contains 'Autostart' -or $evidence -contains 'ScheduledTask') { $flags.Add('Autostart') }
    New-SoftwareRecord -Name ([System.IO.Path]::GetFileNameWithoutExtension($Candidate.Path)) -Source Portable -Property @{
        InstallType     = 'Portable'
        Scope           = if (Test-PathExcluded -Path $Candidate.Path -Exclusion @($env:USERPROFILE)) { 'User' } else { 'Machine' }
        InstallLocation = [System.IO.Path]::GetDirectoryName($Candidate.Path)
        FilePath        = $Candidate.Path
        Evidence        = $evidence
        LastRun         = $Candidate.LastRun
        RunCount        = if ($Candidate.RunCount) { [int] $Candidate.RunCount } else { $null }
        Flags           = [string[]] $flags
    }
}

function Get-TempDirectory {
    @($env:TEMP, [System.IO.Path]::GetTempPath(), (Join-Path $env:windir 'Temp')) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique
}

function Get-WritableWindowsDirectory {
    # Unterordner von %windir%, in die normale Benutzer schreiben dürfen (beliebte Ablage für Schadsoftware).
    'Temp', 'Tasks', 'Tracing' | ForEach-Object { Join-Path $env:windir $_ }
}

function Get-ContainerDirectory {
    # Sammelordner, die nie als Ganzes einem Programm zugerechnet werden.
    $known = Get-KnownFolderMap
    $dirs = @(
        [Environment]::GetFolderPath('UserProfile'), [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyDocuments'), $env:LOCALAPPDATA, $env:APPDATA,
        (Join-Path $env:LOCALAPPDATA 'Programs'), $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $known['{374DE290-123F-4565-9164-39C4925E467B}']
    ) + @(Get-TempDirectory) + @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.RootDirectory.FullName })
    $dirs | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique
}

function Get-VersionPrefix {
    # Erste drei Versionsteile, numerisch normalisiert: "26.05" -> "26.5.0", "3.13.15150.1013" -> "3.13.15150".
    param([string] $Version)
    if ($Version -notmatch '^\d+(\.\d+)*') { return $null }
    $parts = @($Matches[0] -split '\.' | Select-Object -First 3 | ForEach-Object { [string] [long] $_ })
    while ($parts.Count -lt 3) { $parts += '0' }
    $parts -join '.'
}

function Remove-InstalledMatch {
    <#
    .SYNOPSIS
        Entfernt Dateien, die zu einem installierten Programm gehören, dessen Registry-Eintrag
        keinen Pfad nennt (z. B. Python): gleicher Hersteller, Name und Version (erste drei Teile).
    .DESCRIPTION
        Eine Datei mit Herstellerangabe ist nur bei gültiger Signatur ein Treffer (die Angabe
        kann jeder setzen); ohne Herstellerangabe zählen Name und Version.
        Liegt ein Treffer nicht in einem Sammelordner oder einer Scan-Wurzel, wird sein Ordner
        samt Unterordnern als installiert betrachtet (z. B. Python313\Scripts\pip.exe). Sichtbar
        bleiben dort Dateien mit eigenem Produktnamen und anderem Hersteller als der Treffer.
    #>
    param([object[]] $Info, [object[]] $Inventory, [string[]] $ScanRoot = @())

    $index = foreach ($record in $Inventory) {
        $pub = Get-PublisherKey $record.Publisher
        $ver = Get-VersionPrefix $record.Version
        if ($pub -and $ver -and $record.Name) { @{ Publisher = $pub; Version = $ver; Name = $record.Name.ToLowerInvariant() } }
    }
    $containers = @(Get-ContainerDirectory) + @($ScanRoot | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })

    $matchedFiles = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $matchedDirs = [System.Collections.Generic.List[object]]::new()
    foreach ($i in $Info) {
        # Ohne Herstellerangabe in der Datei (der Signierer ist oft ein anderer) zählen nur Name und Version.
        $pub = Get-PublisherKey $i.Company
        if ($pub -and $i.SignatureStatus -ne 'Valid') { continue }
        $ver = Get-VersionPrefix $i.Version
        $name = (Get-ExecutableProductName $i).ToLowerInvariant()
        if (-not $ver -or $name.Length -lt 3) { continue }
        $hit = $index | Where-Object {
            (-not $pub -or $_.Publisher -eq $pub) -and $_.Version -eq $ver -and ($_.Name.StartsWith($name) -or $name.StartsWith($_.Name))
        } | Select-Object -First 1
        if (-not $hit) { continue }
        [void] $matchedFiles.Add($i.Path)
        if ($i.Directory.TrimEnd('\') -notin $containers) { $matchedDirs.Add(@{ Directory = $i.Directory; Publisher = $hit.Publisher }) }
    }

    foreach ($i in $Info) {
        if ($matchedFiles.Contains($i.Path)) { continue }
        $dir = $matchedDirs | Where-Object { Test-PathExcluded -Path $i.Path -Exclusion @($_.Directory) } | Select-Object -First 1
        if ($dir) {
            $ownProduct = [bool] ($i.Name -or $i.Description)
            $filePublisher = Get-PublisherKey $i.Company
            if (-not ($ownProduct -and $filePublisher -and $filePublisher -ne $dir.Publisher)) { continue }
        }
        $i
    }
}

function Merge-NestedComponent {
    <#
    .SYNOPSIS
        Ordnet .exe-Dateien in Unterordnern eines erkannten Programms diesem Programm zu
        (z. B. Hilfsprogramme in resources\ oder node_modules\).
    .DESCRIPTION
        Als Programm gilt ein Datensatz mit Produktnamen aus der Versionsinfo, der nicht
        direkt in einem Sammelordner (Downloads, Desktop, Laufwerkswurzel ...) oder einer
        Scan-Wurzel liegt. Spuren und Warnsignale der Unterdateien gehen auf das Programm über.
    #>
    param([object[]] $Record, [string[]] $ScanRoot = @())

    $containers = @(Get-ContainerDirectory) + @($ScanRoot | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })
    $roots = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $Record | Where-Object { $_ } | Sort-Object { $_.InstallLocation.Length }, FilePath) {
        # Nur echte Unterordner: Andere Produkte im selben Ordner bleiben eigene Datensätze.
        $parent = $roots | Where-Object { Test-PathExcluded -Path $r.InstallLocation -Exclusion @($_.InstallLocation) } | Select-Object -First 1
        if ($parent) {
            $parent.Evidence = [string[]] @(@($parent.Evidence) + @($r.Evidence) | Select-Object -Unique | Sort-Object)
            $parent.Flags = [string[]] @(@($parent.Flags) + @($r.Flags) | Where-Object { $_ } | Select-Object -Unique)
            continue
        }
        if ($r.HasProductName -and $r.InstallLocation.TrimEnd('\') -notin $containers) { $roots.Add($r) }
        $r.PSObject.Properties.Remove('HasProductName')
        $r
    }
}

function Merge-PortableCopy {
    <#
    .SYNOPSIS
        Fasst identische Kopien (gleicher Name, Version, Größe und ggf. Hash) zu einem Datensatz zusammen.
    .DESCRIPTION
        Hauptfundort ist die Kopie mit Ausführungsspuren, sonst der kürzeste Pfad.
        Die übrigen Fundorte landen in CopyPaths.
    #>
    param([object[]] $Record)

    foreach ($group in $Record | Where-Object { $_ } | Group-Object CopyKey) {
        $sorted = @($group.Group | Sort-Object @{ Expression = { @($_.Evidence | Where-Object { $_ -ne 'FileScan' }).Count }; Descending = $true },
            @{ Expression = { $_.FilePath.Length } }, FilePath)
        $main = $sorted[0]
        if ($sorted.Count -gt 1) {
            $others = $sorted | Select-Object -Skip 1
            $main.CopyPaths = [string[]] @($others | ForEach-Object FilePath)
            $main.Evidence = [string[]] @($sorted | ForEach-Object { $_.Evidence } | Select-Object -Unique | Sort-Object)
            $main.Flags = [string[]] @($sorted | ForEach-Object { $_.Flags } | Where-Object { $_ } | Select-Object -Unique)
            $lastRun = $sorted | ForEach-Object LastRun | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
            if ($lastRun) { $main.LastRun = $lastRun }
        }
        $main.PSObject.Properties.Remove('CopyKey')
        $main
    }
}

function ConvertTo-DriveRoot {
    param([string] $Drive)
    if ($Drive -notmatch '^(?<letter>[A-Za-z]):?\\?$') { throw "Ungültige Laufwerksangabe '$Drive' (erwartet z. B. C oder D:)." }
    "$($Matches.letter.ToUpperInvariant()):\"
}

function Test-PathExcluded {
    param([string] $Path, [string[]] $Exclusion)
    foreach ($dir in $Exclusion) {
        if ($Path.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Get-ExecutableProductName {
    param($Info)
    if ($Info.Name) { return $Info.Name }
    if ($Info.Description) { return $Info.Description }
    [System.IO.Path]::GetFileNameWithoutExtension($Info.Path)
}

function ConvertTo-PortableRecord {
    <#
    .SYNOPSIS
        Fasst die .exe-Dateien eines Produkts in einem Ordner zu einem Datensatz zusammen.
    .DESCRIPTION
        Hauptdatei ist die mit Ausführungsspuren, sonst die größte (Hilfsprogramme sind meist kleiner).
    #>
    param([object[]] $File)

    $main = $File | Sort-Object @{ Expression = { @($_.Evidence | Where-Object { $_ -ne 'FileScan' }).Count -gt 0 }; Descending = $true },
        @{ Expression = 'Length'; Descending = $true }, Path | Select-Object -First 1
    $evidence = [string[]] @($File | ForEach-Object { $_.Evidence } | Select-Object -Unique | Sort-Object)
    $lastRun = $File | ForEach-Object LastRun | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1
    $runCount = ($File | ForEach-Object RunCount | Where-Object { $_ } | Measure-Object -Maximum).Maximum

    $flags = [System.Collections.Generic.List[string]]::new()
    switch ($main.SignatureStatus) {
        'Valid' { }
        'NotSigned' { $flags.Add('Unsigned') }
        $null { }
        default { $flags.Add('InvalidSignature') }
    }
    $downloads = (Get-KnownFolderMap)['{374DE290-123F-4565-9164-39C4925E467B}']
    if (Test-PathExcluded -Path $main.Path -Exclusion (@($downloads) + (Get-TempDirectory))) {
        $flags.Add('InDownloadsOrTemp')
    }
    if ($evidence -contains 'Autostart' -or $evidence -contains 'ScheduledTask') { $flags.Add('Autostart') }

    $name = Get-ExecutableProductName $main
    $record = New-SoftwareRecord -Name $name -Source Portable -Property @{
        Publisher       = if ($main.Company) { $main.Company } else { $main.Signer }
        Version         = $main.Version
        InstallType     = 'Portable'
        Scope           = if (Test-PathExcluded -Path $main.Path -Exclusion @($env:USERPROFILE)) { 'User' } else { 'Machine' }
        Architecture    = $main.Machine
        InstallLocation = $main.Directory
        FilePath        = $main.Path
        Sha256          = $main.Sha256
        SignatureStatus = $main.SignatureStatus
        Signer          = $main.Signer
        Evidence        = $evidence
        LastRun         = $lastRun
        RunCount        = if ($runCount) { [int] $runCount } else { $null }
        Flags           = [string[]] $flags
    }
    # Hilfsfelder für Merge-NestedComponent und Merge-PortableCopy; werden dort wieder entfernt.
    $copyKey = "$name|$($main.Version)|$($main.Length)|$($main.Sha256)".ToLowerInvariant()
    $record | Add-Member -NotePropertyMembers @{ CopyKey = $copyKey; HasProductName = [bool] ($main.Name -or $main.Description) } -PassThru
}

function Add-MultipleVersionFlag {
    # Markiert Programme, die in mehreren Ordnern in unterschiedlichen Versionen liegen.
    param([object[]] $Record)
    foreach ($group in $Record | Where-Object { $_ } | Group-Object { "$($_.Name)|$($_.Publisher)".ToLowerInvariant() }) {
        if (@($group.Group | ForEach-Object Version | Select-Object -Unique).Count -gt 1) {
            foreach ($r in $group.Group) { $r.Flags = [string[]] @(@($r.Flags) + 'MultipleVersions' | Where-Object { $_ }) }
        }
    }
}
