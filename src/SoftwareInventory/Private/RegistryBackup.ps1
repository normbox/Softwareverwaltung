# Sicherung von Registry-Schlüsseln vor dem Entfernen verwaister Einträge (Remove-OrphanedEntry).
# Liegt unter logs\registry-backup\ und hat eine eigene Frist (365 Tage), unabhängig von der normalen
# Selbstbereinigung und nicht in deren Größengrenze.

$script:RegistryBackupRetentionDays = 365

function Get-RegistryBackupDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\registry-backup'
}

function Get-RegistryBackupFileName {
    # <ActionId>_<bereinigter Programmname>.reg; Name ohne Sonderzeichen, höchstens 60 Zeichen.
    param([string] $ActionId, [string] $Name)
    $clean = ($Name -replace '[^\w.\-]+', '_').Trim('_', '.')
    if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60).TrimEnd('_', '.') }
    if (-not $clean) { $clean = 'Eintrag' }
    "${ActionId}_$clean.reg"
}

function Invoke-RegExport {
    # reg.exe aus System32 (fester Pfad, nie über PATH): exportiert den Schlüssel; liefert den Exit-Code.
    param([Parameter(Mandatory)] [string] $NativeKey, [Parameter(Mandatory)] [string] $File)
    $reg = Join-Path ([Environment]::GetFolderPath('System')) 'reg.exe'
    $info = [System.Diagnostics.ProcessStartInfo]::new($reg)
    foreach ($a in 'export', $NativeKey, $File, '/y') { $info.ArgumentList.Add($a) }
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $null = $process.StandardOutput.ReadToEnd(); $null = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $process.ExitCode
    }
    finally { $process.Dispose() }
}

function Test-RegistryBackup {
    <#
    .SYNOPSIS
        Ist die Sicherung brauchbar? Datei vorhanden, nicht leer und mit der Zeile [<Schlüssel>].
    .OUTPUTS
        $null, wenn sie passt; sonst der Grund: Missing, Empty oder KeyNotFound.
    #>
    param([string] $File, [string] $NativeKey)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return 'Missing' }
    if ((Get-Item -LiteralPath $File).Length -eq 0) { return 'Empty' }
    # reg export schreibt UTF-16 mit BOM; Get-Content erkennt das.
    $text = Get-Content -LiteralPath $File -Raw
    if (-not $text -or $text.IndexOf("[$NativeKey]", [StringComparison]::OrdinalIgnoreCase) -lt 0) { return 'KeyNotFound' }
    $null
}

function Remove-ExpiredRegistryBackup {
    # Löscht Sicherungen älter als 365 Tage; Anzahl gelöschter Dateien.
    param([string] $Root = (Get-AppDataDirectory), [int] $RetentionDays = $script:RegistryBackupRetentionDays)
    $directory = Join-Path $Root 'logs\registry-backup'
    if (-not (Test-Path -LiteralPath $directory)) { return 0 }
    $cutoff = [datetime]::UtcNow.AddDays(-$RetentionDays)
    $deleted = 0
    foreach ($f in Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction SilentlyContinue) {
        if ($f.LastWriteTimeUtc -lt $cutoff -and (Remove-CleanupFile $f)) { $deleted++ }
    }
    $deleted
}
