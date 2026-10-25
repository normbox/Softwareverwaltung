# Aktionsprotokoll und Selbstbereinigung des App-Ordners.
#
# Protokoll: %LOCALAPPDATA%\SoftwareInventory\logs\actions\<yyyy-MM-dd>.jsonl (Datum in UTC),
# eine JSON-Zeile pro Eintrag. Jede Aktion schreibt „Started“ und „Completed“ mit derselben ActionId.
# Geschrieben wird nur vom Prozess ohne Adminrechte; der erhöhte Helfer schreibt nie hierher.
#
# Installer-Logs: logs\installer\<ActionId>.log; nach Erfolg gelöscht, bei Fehlern als .zip aufgehoben.
# Bereinigung beim Laden des Moduls: logs\ und cache\ höchstens LogRetentionDays alt und zusammen
# höchstens LogMaxSizeMB groß, Ältestes zuerst. Gespeicherte Scans (scans\) sind Nutzdaten und bleiben.

$script:ActionLogSchemaVersion = 1
$script:ActionLogMutexName = 'Local\SoftwareInventory.ActionLog'

function Get-AppDataDirectory {
    Join-Path $env:LOCALAPPDATA 'SoftwareInventory'
}

function Get-ActionLogDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\actions'
}

function Get-InstallerLogDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\installer'
}

function Get-CurrentUserName {
    [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

function Write-ActionLogEntry {
    <#
    .SYNOPSIS
        Hängt einen Eintrag an das Protokoll an.
    .DESCRIPTION
        Ein benannter Mutex verhindert, dass sich gleichzeitige Schreiber vermischen.
        Bekannte API-Schlüssel werden vor dem Schreiben entfernt.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Started', 'Completed')] [string] $Phase,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Data
    )

    $now = [datetime]::UtcNow
    $entry = [ordered]@{
        SchemaVersion = $script:ActionLogSchemaVersion
        Timestamp     = $now.ToString('o')
        Phase         = $Phase
        User          = Get-CurrentUserName
        ModuleVersion = [string] (Get-SoftwareInventoryVersion)
    }
    foreach ($key in $Data.Keys) { if (-not $entry.Contains($key)) { $entry[$key] = $Data[$key] } }
    $line = Protect-SecretText ($entry | ConvertTo-Json -Compress -Depth 5)

    $directory = Get-ActionLogDirectory
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Join-Path $directory ($now.ToString('yyyy-MM-dd') + '.jsonl')
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($line + "`n")

    $mutex = [System.Threading.Mutex]::new($false, $script:ActionLogMutexName)
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne([timespan]::FromSeconds(10)) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { Write-Warning 'Protokoll ist gesperrt; Eintrag wird trotzdem geschrieben.' }
        $stream = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-SoftwareInventoryVersion {
    $module = $ExecutionContext.SessionState.Module
    if ($module) { $module.Version } else { $null }
}

function Read-ActionLogEntry {
    <#
    .SYNOPSIS
        Liest alle Protokollzeilen; kaputte oder abgeschnittene Zeilen werden übersprungen.
    #>
    param([string] $Directory = (Get-ActionLogDirectory))

    if (-not (Test-Path -LiteralPath $Directory)) { return }
    $bad = 0
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Filter '*.jsonl' -File | Sort-Object Name) {
        try {
            # FileShare.ReadWrite: ein laufender Schreiber darf nicht blockieren.
            $stream = [System.IO.FileStream]::new($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
            $content = $reader.ReadToEnd()
            $reader.Dispose()
        }
        catch {
            Write-Warning "Protokolldatei nicht lesbar: $($file.Name)"
            continue
        }
        foreach ($line in $content -split "`r?`n") {
            if (-not $line.Trim()) { continue }
            try {
                $entry = $line | ConvertFrom-Json -DateKind String -ErrorAction Stop
                if (-not $entry.PSObject.Properties['ActionId'] -or -not $entry.PSObject.Properties['Phase']) { throw 'Pflichtfelder fehlen' }
                if ($entry.PSObject.Properties['SchemaVersion'] -and $entry.SchemaVersion -gt $script:ActionLogSchemaVersion) { continue }
                $entry
            }
            catch {
                $bad++
            }
        }
    }
    if ($bad) { Write-Warning "$bad beschädigte Protokollzeile(n) übersprungen." }
}

function Complete-InstallerLog {
    <#
    .SYNOPSIS
        Räumt ein Installer-Log nach der Aktion auf: bei Erfolg löschen, sonst als .zip aufheben.
    .OUTPUTS
        Pfad der aufgehobenen .zip-Datei oder $null.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [bool] $Keep
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        if (-not $Keep) { return $null }
        $zip = [System.IO.Path]::ChangeExtension($Path, '.zip')
        Compress-Archive -LiteralPath $Path -DestinationPath $zip -Force
        $zip
    }
    catch {
        Write-Warning "Installer-Log konnte nicht komprimiert werden: $_"
        $null
    }
    finally {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AppDataCleanup {
    <#
    .SYNOPSIS
        Löscht alte Logs und Zwischenspeicher: zuerst nach Alter, dann nach Gesamtgröße (Ältestes zuerst).
    .DESCRIPTION
        Betrifft nur logs\ und cache\ im App-Ordner. Gesperrte Dateien werden übersprungen.
    .OUTPUTS
        Anzahl gelöschter Dateien.
    #>
    param(
        [int] $RetentionDays = $script:DefaultLogRetentionDays,
        [int] $MaxSizeMB = $script:DefaultLogMaxSizeMB,
        [string] $Root = (Get-AppDataDirectory)
    )

    $folders = @('logs', 'cache') | ForEach-Object { Join-Path $Root $_ } | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $folders) { return 0 }
    $files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($folder in $folders) {
        foreach ($f in Get-ChildItem -LiteralPath $folder -File -Recurse -Force -ErrorAction SilentlyContinue) { $files.Add($f) }
    }

    $deleted = 0
    $cutoff = [datetime]::UtcNow.AddDays(-$RetentionDays)
    $remaining = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    foreach ($f in $files | Sort-Object LastWriteTimeUtc) {
        if ($f.LastWriteTimeUtc -lt $cutoff -and (Remove-CleanupFile $f)) { $deleted++ } else { $remaining.Add($f) }
    }

    $limit = [long] $MaxSizeMB * 1MB
    $total = ($remaining | Measure-Object Length -Sum).Sum
    foreach ($f in $remaining) {
        if ($total -le $limit) { break }
        $length = $f.Length   # nach Delete() ist Length nicht mehr abrufbar
        if (Remove-CleanupFile $f) { $deleted++; $total -= $length }
    }

    foreach ($folder in $folders) {
        Get-ChildItem -LiteralPath $folder -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    $deleted
}

function Remove-CleanupFile {
    param([System.IO.FileInfo] $File)
    try {
        $File.Delete()
        $true
    }
    catch {
        Write-Verbose "Nicht gelöscht (in Benutzung?): $($File.FullName)"
        $false
    }
}
