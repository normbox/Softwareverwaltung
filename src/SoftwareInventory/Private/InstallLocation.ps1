# Installationsordner eines Programms ermitteln (Detailansicht). Quellen in fester Reihenfolge:
# Installer-Eintrag (bzw. App-Paket, Dateisuche) gilt als sicher; Ordner aus Programmsymbol,
# Deinstallationsbefehl und MSI-Komponenten sind abgeleitet („vermutlich“) und zählen nur, wenn dort
# wirklich ein Programm (.exe) liegt. Zwischenspeicher des Installers werden nie verwendet.

# Deinstallations- und Setup-Programme zählen nicht als „Programm“ im Ordner.
$script:UninstallerPattern = '^(unins|uninst|setup)|uninstall'

function Get-InstallerCacheRoot {
    # Ordner, die nie als Installationsordner gelten: Zwischenspeicher des Installers, Temp, System.
    @(
        (Join-Path $env:windir 'Installer'), (Join-Path $env:windir 'Temp'), (Join-Path $env:windir 'System32'),
        (Join-Path $env:windir 'SysWOW64'), (Join-Path $env:ProgramData 'Package Cache'), [System.IO.Path]::GetTempPath()
    )
}

function Test-InstallerCachePath {
    param([string] $Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\') + '\'
    $roots = Get-InstallerCacheRoot | ForEach-Object { $_.TrimEnd('\') + '\' }
    foreach ($root in $roots) { if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
    # Symbol-Zwischenspeicher je Benutzer (AppData\Roaming\Microsoft\Installer\{GUID}\icon.exe) und von InstallShield
    $full -match '\\AppData\\[^\\]+\\(Microsoft\\)?Installer\\' -or $full -match '\\InstallShield Installation Information\\'
}

function Test-ProgramFolder {
    # Ein abgeleiteter Ordner zählt nur, wenn dort eine .exe liegt, die kein Deinstallations- oder Setup-Programm ist.
    param([string] $Folder)
    if (-not $Folder -or -not [System.IO.Directory]::Exists($Folder)) { return $false }
    try {
        foreach ($file in [System.IO.Directory]::EnumerateFiles($Folder, '*.exe')) {
            if ([System.IO.Path]::GetFileName($file) -notmatch $script:UninstallerPattern) { return $true }
        }
    }
    catch { Write-Verbose "Ordner nicht lesbar: $Folder" }
    $false
}

function Get-MsiComponentPath {
    # Dateipfade der installierten Komponenten eines MSI-Produkts (Windows Installer, nur lesend).
    param([string] $ProductCode)
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $package = $installer.ProductInfo($ProductCode, 'LocalPackage')
    $database = $installer.OpenDatabase($package, 0)
    $view = $database.OpenView('SELECT `ComponentId` FROM `Component`')
    $view.Execute()
    try {
        while ($row = $view.Fetch()) {
            $id = $row.StringData(1)
            if (-not $id) { continue }
            $path = $installer.ComponentPath($ProductCode, $id)
            # Registry-Komponenten beginnen mit z. B. „02:\“; nur Dateipfade zählen.
            if ($path -and [System.IO.Path]::IsPathRooted($path) -and $path -notmatch '^\d\d:') { $path }
        }
    }
    finally { $view.Close() }
}

function Get-MsiProgramFolder {
    # Gemeinsamer Ordner der .exe-Komponenten (ohne Deinstallations- und Setup-Programme).
    param([string] $ProductCode)
    $folders = @(Get-MsiComponentPath -ProductCode $ProductCode |
            Where-Object { $_ -match '\.exe$' -and [System.IO.Path]::GetFileName($_) -notmatch $script:UninstallerPattern } |
            ForEach-Object { [System.IO.Path]::GetDirectoryName($_) } | Sort-Object -Unique)
    if (-not $folders) { return $null }
    $common = $folders[0]
    foreach ($f in $folders) {
        while ($common -and -not ($f + '\').StartsWith($common.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $common = [System.IO.Path]::GetDirectoryName($common)
        }
    }
    # Nur ein Laufwerk als Gemeinsamkeit ist kein Programmordner.
    if (-not $common -or $common.TrimEnd('\').Length -le 2) { return $folders[0] }
    $common
}

function New-InstallLocationResult {
    param($Record, [string] $Path, [string] $Source, [bool] $Certain, $Reason)
    $windowsApps = (Join-Path $env:ProgramFiles 'WindowsApps').TrimEnd('\') + '\'
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.InstallLocation'
        Name       = $Record.Name
        Path       = $Path
        Source     = $Source
        Certain    = $Certain
        Note       = if ($Source) { New-InventoryMessage "InstallLocationFrom$Source" } else { $null }
        Reason     = $Reason
        # Store-Apps liegen in WindowsApps; der Ordner ist für Benutzer gesperrt, daher nicht öffnen.
        CanOpen    = [bool] ($Path -and $Source -ne 'AppPackage' -and -not ($Path.TrimEnd('\') + '\').StartsWith($windowsApps, [StringComparison]::OrdinalIgnoreCase))
    }
}
