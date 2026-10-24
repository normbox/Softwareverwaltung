function Find-ExecutableFile {
    <#
    .SYNOPSIS
        Sucht .exe-Dateien unterhalb der angegebenen Ordner.
    .DESCRIPTION
        Durchläuft die Ordner selbst statt Get-ChildItem -Recurse, damit ausgeschlossene
        Teilbäume (Windows, installierte Programme) gar nicht erst betreten werden.
        Verknüpfte Ordner (Junctions, Symlinks) und unlesbare Ordner werden übersprungen.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string[]] $Root,
        [string[]] $ExcludeDirectory = @()
    )

    $exclude = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($dir in $ExcludeDirectory) { if ($dir) { [void] $exclude.Add($dir.TrimEnd('\')) } }

    $pending = [System.Collections.Generic.Stack[string]]::new()
    foreach ($r in $Root) { if (Test-Path -LiteralPath $r -PathType Container) { $pending.Push($r.TrimEnd('\') + '\') } }
    $reparse = [System.IO.FileAttributes]::ReparsePoint
    $visited = 0

    while ($pending.Count) {
        $dir = $pending.Pop()
        $visited++
        if ($visited % 2000 -eq 0) {
            Write-Progress -Activity 'Suche nach Programmdateien' -Status $dir -Id 1
        }

        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, '*.exe')) { $file }
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if ($exclude.Contains($sub)) { continue }
                if (([System.IO.File]::GetAttributes($sub) -band $reparse) -ne 0) { continue }
                $pending.Push($sub)
            }
        }
        catch {
            Write-Verbose "Übersprungen: $dir ($($_.Exception.GetType().Name))"
        }
    }
    Write-Progress -Activity 'Suche nach Programmdateien' -Id 1 -Completed
}

function Get-ScanExclusion {
    <#
    .SYNOPSIS
        Ordner, die beim Dateiscan nicht betreten werden: Windows, Systemordner und
        die Ordner installierter Programme aus dem Inventar.
    #>
    param([object[]] $Inventory = @())

    $static = @(
        $env:windir
        (Join-Path $env:ProgramFiles 'WindowsApps')
        (Join-Path $env:ProgramData 'Package Cache')
        (Join-Path $env:ProgramData 'Microsoft')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
        (Join-Path $env:LOCALAPPDATA 'Packages')
    )
    # Update-Zwischenspeicher von Electron-Apps (%LOCALAPPDATA%\<app>-updater) enthalten nur Installer.
    $updaterCaches = Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Directory -Filter '*-updater' -ErrorAction SilentlyContinue |
        ForEach-Object FullName
    $perDrive = foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        # Store-Apps und Xbox-Spiele auf anderen Laufwerken verwaltet Windows selbst.
        foreach ($name in '$Recycle.Bin', 'System Volume Information', 'Windows.old', '$WinREAgent', '$SysReset', 'WindowsApps', 'WpSystem', 'XboxGames') {
            Join-Path $drive.RootDirectory.FullName $name
        }
    }
    $tooBroad = @(Get-TooBroadDirectory)
    $installed = foreach ($record in $Inventory) {
        $iconDir = if ($record.DisplayIcon -match '\.exe$') { Split-Path -Parent $record.DisplayIcon }
        foreach ($dir in @($record.InstallLocation; (Get-UninstallerDirectory $record.UninstallString); $iconDir)) {
            if (Test-SpecificInstallDirectory -Path $dir -TooBroad $tooBroad) { $dir.TrimEnd('\') }
        }
    }
    @($static) + @($updaterCaches) + @($perDrive) + @($installed) | Where-Object { $_ } | Select-Object -Unique
}

function Get-PublisherKey {
    # Vergleichsschlüssel für Hersteller: erstes Wort ohne Satzzeichen, z. B. "Acronis International GmbH" -> "acronis".
    param([string] $Publisher)
    if (-not $Publisher) { return $null }
    $word = ($Publisher.ToLowerInvariant() -replace '[^\p{L}\p{N} ]', ' ').Trim() -split '\s+' | Select-Object -First 1
    if ($word.Length -ge 3) { $word }
}

function Get-VendorDirectory {
    <#
    .SYNOPSIS
        Herstellerordner einer Datei unter Program Files oder ProgramData, z. B.
        C:\Program Files\Brother\iPrint\x.exe -> C:\Program Files\Brother. Sonst $null.
    .DESCRIPTION
        In Program Files schreiben nur Installer mit Administratorrechten; ProgramData ist
        dagegen für normale Benutzer beschreibbar. Deshalb zählt ein Herstellerordner nur über
        gültig signierte Dateien (siehe Test-InstalledProgramFile).
        Common Files steht vor Program Files, damit dort der Unterordner zählt.
    #>
    param([string] $Path)
    $bases = @($env:CommonProgramFiles, ${env:CommonProgramFiles(x86)}, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) |
        Where-Object { $_ }
    foreach ($base in $bases) {
        $prefix = $base.TrimEnd('\') + '\'
        if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $first = $Path.Substring($prefix.Length).Split('\')[0]
        # Datei direkt im Basisordner hat keinen Herstellerordner.
        if ($Path.Substring($prefix.Length) -eq $first) { return $null }
        return $prefix + $first
    }
    $null
}

function Test-InstalledProgramFile {
    <#
    .SYNOPSIS
        Erkennt Dateien unter Program Files oder ProgramData, die zu einer Installation
        gehören, deren Registry-Eintrag keinen Installationsordner nennt: Hersteller der
        Datei ist zugleich Herausgeber eines installierten Programms.
    .DESCRIPTION
        Die Herstellerangabe in der Versionsinfo kann jeder setzen; sie zählt daher nur bei
        gültiger Signatur. Ohne gültige Signatur keine Herstellerzuordnung.
    #>
    param($Info, [System.Collections.Generic.HashSet[string]] $InstalledPublisher)
    if ($Info.SignatureStatus -ne 'Valid') { return $false }
    if (-not (Get-VendorDirectory $Info.Path)) { return $false }
    foreach ($candidate in $Info.Company, $Info.Signer) {
        $key = Get-PublisherKey $candidate
        if ($key -and $InstalledPublisher.Contains($key)) { return $true }
    }
    $false
}

function Get-UninstallerDirectory {
    # Ordner des Deinstallationsprogramms; msiexec und rundll32 liegen im Windows-Ordner und zählen nicht.
    param([string] $UninstallString)
    $exe = ConvertFrom-CommandLine $UninstallString
    if (-not $exe -or $exe -match '\\(msiexec|rundll32)\.exe$') { return $null }
    Split-Path -Parent $exe
}

function Get-TooBroadDirectory {
    # Sammelordner (Profil, Desktop, Dokumente, Downloads, Temp, Program Files ...) plus Systemordner.
    @(Get-ContainerDirectory) + @($env:ProgramData, $env:windir, $env:CommonProgramFiles, ${env:CommonProgramFiles(x86)}) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique
}

function Test-SpecificInstallDirectory {
    # Verhindert, dass fehlerhafte Einträge (z. B. InstallLocation = C:\Program Files) ganze Bäume ausschließen.
    param([string] $Path, [string[]] $TooBroad = (Get-TooBroadDirectory))
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\') { return $false }
    $normalized = $Path.TrimEnd('\')
    if ($normalized -in $TooBroad) { return $false }
    # Nur die Laufwerkswurzel selbst ist zu breit; D:\Steam ist ein gültiger Installationsordner.
    ($normalized -split '\\').Count -ge 2
}
