# Sicherung von Registry-Schlüsseln vor dem Entfernen verwaister Einträge (Remove-OrphanedEntry).
# Liegt unter logs\registry-backup\ und hat eine eigene Frist (365 Tage), unabhängig von der normalen
# Selbstbereinigung und nicht in deren Größengrenze. Je Sicherung gibt es zwei Dateien mit gleichem Namen:
# <ActionId>_<Name>.reg (reg export) und <ActionId>_<Name>.json (Angaben zur Sicherung, nur Codes, nie Text).

$script:RegistryBackupRetentionDays = 365
$script:RegistryBackupMaxBytes = 16MB
$script:RegistryBackupSidecarMaxBytes = 64KB
# Nur diese Gründe übernimmt das Modul in die Begleitdatei; alles andere wird verworfen.
$script:KnownBackupReasonCodes = @('OrphanedEntry', 'NewerInstallNextTo')

function Get-RegistryBackupDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\registry-backup'
}

function Get-RegistryBackupFileName {
    # <ActionId>_<bereinigter Programmname>.reg; Name ohne Pfadzeichen, ohne "..", ohne reservierte
    # Gerätenamen, höchstens 60 Zeichen.
    param([string] $ActionId, [string] $Name)
    $clean = ($Name -replace '[^\w.\-]+', '_')
    $clean = ($clean -replace '\.{2,}', '.').Trim('_', '.')
    if ($clean.Length -gt 60) { $clean = $clean.Substring(0, 60).TrimEnd('_', '.') }
    if (-not $clean) { $clean = 'Eintrag' }
    if ($clean -match '^(?i:CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\..*)?$') { $clean = "_$clean" }
    "${ActionId}_$clean.reg"
}

function Get-RegistryBackupId {
    # Die Kennung einer Sicherung ist die ActionId (GUID) am Anfang des Dateinamens; sonst $null.
    param([string] $File)
    $name = [System.IO.Path]::GetFileName($File)
    if ($name -match '^(?<id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})_') { $Matches.id.ToLowerInvariant() }
}

function Get-RegistryBackupSidecarPath {
    param([string] $File)
    [System.IO.Path]::ChangeExtension($File, '.json')
}

function Invoke-RegExport {
    # reg.exe aus System32 (fester Pfad, nie über PATH): exportiert den Schlüssel; liefert den Exit-Code.
    param([Parameter(Mandatory)] [string] $NativeKey, [Parameter(Mandatory)] [string] $File)
    Invoke-RegTool -Argument 'export', $NativeKey, $File, '/y'
}

function Invoke-RegImport {
    # reg.exe aus System32: spielt genau diese (vorher geprüfte) Datei zurück; liefert den Exit-Code.
    param([Parameter(Mandatory)] [string] $File)
    Invoke-RegTool -Argument 'import', $File
}

function Invoke-RegTool {
    param([string[]] $Argument)
    $reg = Join-Path ([Environment]::GetFolderPath('System')) 'reg.exe'
    $info = [System.Diagnostics.ProcessStartInfo]::new($reg)
    foreach ($a in $Argument) { $info.ArgumentList.Add($a) }
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

function ConvertTo-NativeRegistryPath {
    # HKCU:\... bzw. ein Laufwerk wie TestRegistry:\... als nativer Pfad (HKEY_CURRENT_USER\...).
    param([string] $Path)
    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($item) { return $item.Name }
    $Path -replace '^HKCU:', 'HKEY_CURRENT_USER' -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
}

function Get-UninstallLocationNative {
    # Die Uninstall-Zweige mit nativem Pfad, wie ihn reg export in die Datei schreibt.
    foreach ($location in Get-DefaultUninstallLocation) {
        [pscustomobject] @{ NativePath = (ConvertTo-NativeRegistryPath $location.Path); Scope = $location.Scope }
    }
}

function Get-RegistryBackupText {
    <#
    .SYNOPSIS
        Liest die .reg-Datei genau einmal; liefert die Bytes und den daraus gelesenen Text.
    .OUTPUTS
        @{ Problem; Bytes; Text } (Problem ist $null, wenn alles passt; sonst Missing, Empty, TooLarge oder BadEncoding. reg export schreibt
        immer UTF-16 (Little Endian) mit Bytefolge FF FE am Anfang; alles andere gilt nicht als Sicherung.
    #>
    param([string] $File)
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) { return @{ Problem = 'Missing'; Bytes = $null; Text = $null } }
    if ((Get-Item -LiteralPath $File).Length -gt $script:RegistryBackupMaxBytes) { return @{ Problem = 'TooLarge'; Bytes = $null; Text = $null } }
    $bytes = [System.IO.File]::ReadAllBytes($File)
    if ($bytes.Length -eq 0) { return @{ Problem = 'Empty'; Bytes = $null; Text = $null } }
    if ($bytes.Length -lt 2 -or $bytes[0] -ne 0xFF -or $bytes[1] -ne 0xFE) { return @{ Problem = 'BadEncoding'; Bytes = $null; Text = $null } }
    @{ Problem = $null; Bytes = $bytes; Text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
}

function Test-RegistryBackupContent {
    <#
    .SYNOPSIS
        Prüft den Inhalt einer .reg-Sicherung streng, bevor sie zurückgespielt wird.
    .DESCRIPTION
        Erlaubt ist genau ein Hauptschlüssel (der Schlüssel aus der Begleitdatei) direkt unter einem
        Uninstall-Zweig des erlaubten Bereichs (-Scope, Vorgabe User); jeder weitere Schlüsselkopf muss mit "<Hauptschlüssel>\" beginnen
        (Unterschlüssel). Keine Löschzeilen ([-...]), keine anderen Schlüssel.
    .OUTPUTS
        $null, wenn der Inhalt passt; sonst der Grund: Empty, BadLineBreak, BadHeader, DeleteLine, BadKeyLine, KeyNotFound,
        KeyMismatch, KeyOutside, KeyNotUninstall, MachineNotYet (HKLM, aber nur User erlaubt) oder WrongScope
        (HKCU, aber nur Machine erlaubt). Der Helfer prüft mit denselben Regeln (RegistryBackupRules.cs); beide
        gegen tests/Data/registry-backup-cases.json.
    #>
    param([string] $Text, [string] $NativeKey, [ValidateSet('User', 'Machine')] [string] $Scope = 'User')
    if (-not $Text -or -not $NativeKey) { return 'Empty' }
    # reg export schreibt nur CRLF. Einzelne CR/LF, NUL oder andere Zeilentrenner lehnen wir ab: Würde reg.exe
    # dort anders trennen als diese Prüfung, könnte sich eine Schlüsselzeile an der Prüfung vorbeischmuggeln.
    if ($Text -match "[\x00\x0B\x0C\u0085\u2028\u2029]|\r(?!\n)|(?<!\r)\n") { return 'BadLineBreak' }
    $lines = $Text -split "\r\n"
    if ($lines[0].TrimEnd() -cne 'Windows Registry Editor Version 5.00') { return 'BadHeader' }

    $headers = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines | Select-Object -Skip 1) {
        $t = $line.Trim()
        if (-not $t.StartsWith('[')) { continue }
        if ($t.StartsWith('[-')) { return 'DeleteLine' }
        if ($t -notmatch '^\[(?<key>.+)\]$') { return 'BadKeyLine' }
        $headers.Add($Matches.key)
    }
    if ($headers.Count -eq 0) { return 'KeyNotFound' }
    if (-not [string]::Equals($headers[0], $NativeKey, [StringComparison]::OrdinalIgnoreCase)) { return 'KeyMismatch' }
    $prefix = $NativeKey.TrimEnd('\') + '\'
    for ($i = 1; $i -lt $headers.Count; $i++) {
        if (-not $headers[$i].StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return 'KeyOutside' }
    }

    $cut = $NativeKey.LastIndexOf('\')
    if ($cut -lt 1) { return 'KeyNotUninstall' }
    $parent = $NativeKey.Substring(0, $cut)
    $location = Get-UninstallLocationNative | Where-Object { [string]::Equals($_.NativePath, $parent, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $location) { return 'KeyNotUninstall' }
    if ($location.Scope -ne $Scope) { return $(if ($location.Scope -eq 'Machine') { 'MachineNotYet' } else { 'WrongScope' }) }
    $null
}

function Test-RegistryBackup {
    <#
    .SYNOPSIS
        Ist die Sicherung brauchbar? Datei vorhanden, nicht leer, richtig kodiert und streng geprüft.
    .OUTPUTS
        $null, wenn sie passt; sonst der Grund (siehe Get-RegistryBackupText und Test-RegistryBackupContent).
    #>
    param([string] $File, [string] $NativeKey)
    $content = Get-RegistryBackupText -File $File
    if ($content.Problem) { return $content.Problem }
    Test-RegistryBackupContent -Text $content.Text -NativeKey $NativeKey
}

function ConvertTo-KnownBackupReason {
    # Nur bekannte Grund-Codes mit ihren Argumenten (als kurze Texte); alles andere wird verworfen.
    param($Reasons)
    # Gründe sind Objekte (Meldungen, aus JSON) oder Dictionaries (aus dem Plan).
    $field = { param($o, $n) if ($o -is [System.Collections.IDictionary]) { if ($o.Contains($n)) { $o[$n] } } else { Get-RecordValue $o $n } }
    foreach ($reason in @($Reasons)) {
        if ($null -eq $reason) { continue }
        $code = [string] (& $field $reason 'Code')
        if ($code -cnotin $script:KnownBackupReasonCodes) { continue }
        $reasonArgs = @(@(& $field $reason 'Args') | Where-Object { $null -ne $_ } | Select-Object -First 4 | ForEach-Object {
                $s = [string] $_
                if ($s.Length -gt 200) { $s.Substring(0, 200) } else { $s }
            })
        [ordered]@{ Code = $code; Args = $reasonArgs }
    }
}

function Write-RegistryBackupSidecar {
    # Begleitdatei neben der .reg: nur Codes und Daten, nie Anzeigetexte (die kommen aus der psd1).
    param([string] $File, [string] $ActionId, [string] $Name, [string] $NativeKey, [string] $Scope, $Reasons)
    $data = [ordered]@{
        SchemaVersion = 1
        ActionId      = $ActionId
        CreatedAt     = [datetime]::UtcNow.ToString('o')
        Name          = $Name
        NativeKey     = $NativeKey
        Scope         = $Scope
        Reasons       = @(ConvertTo-KnownBackupReason $Reasons)
    }
    [System.IO.File]::WriteAllText((Get-RegistryBackupSidecarPath $File), ($data | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
}

function Read-RegistryBackupSidecar {
    <#
    .SYNOPSIS
        Liest und prüft die Begleitdatei einer Sicherung.
    .OUTPUTS
        @{ Problem; Data }: Data mit ActionId, Name, NativeKey, Scope, CreatedAt (UTC) und Reasons (Code, Args),
        oder Problem mit MetadataMissing oder MetadataInvalid. Beide Schlüssel sind immer da (StrictMode).
    #>
    param([string] $File)
    $path = Get-RegistryBackupSidecarPath $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Problem = 'MetadataMissing'; Data = $null } }
    if ((Get-Item -LiteralPath $path).Length -gt $script:RegistryBackupSidecarMaxBytes) { return @{ Problem = 'MetadataInvalid'; Data = $null } }
    try { $d = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop }
    catch { return @{ Problem = 'MetadataInvalid'; Data = $null } }
    if ($d -isnot [pscustomobject]) { return @{ Problem = 'MetadataInvalid'; Data = $null } }
    $id = [string] (Get-RecordValue $d 'ActionId')
    $name = [string] (Get-RecordValue $d 'Name')
    $key = [string] (Get-RecordValue $d 'NativeKey')
    $created = Get-RecordValue $d 'CreatedAt'
    $createdAt = [datetime]::MinValue
    if ($created -is [datetime]) { $createdAt = $created.ToUniversalTime() }
    elseif (-not [datetime]::TryParse([string] $created, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref] $createdAt)) {
        return @{ Problem = 'MetadataInvalid'; Data = $null }
    }
    if ((Get-RecordValue $d 'SchemaVersion') -ne 1 -or -not $id -or -not $name -or -not $key -or $id -ine (Get-RegistryBackupId $File)) {
        return @{ Problem = 'MetadataInvalid'; Data = $null }
    }
    @{
        Problem = $null
        Data    = [pscustomobject] @{
            ActionId = $id; Name = $name; NativeKey = $key; Scope = [string] (Get-RecordValue $d 'Scope'); CreatedAt = $createdAt
            Reasons  = @(ConvertTo-KnownBackupReason (Get-RecordValue $d 'Reasons'))
        }
    }
}

function Remove-ExpiredRegistryBackup {
    # Löscht Sicherungen älter als 365 Tage. .reg und .json gehören zusammen: Das Alter bestimmt die .reg,
    # beide Dateien gehen gemeinsam. Eine .json ohne .reg (Rest) geht nach einem Tag. Anzahl gelöschter Dateien.
    param([string] $Root = (Get-AppDataDirectory), [int] $RetentionDays = $script:RegistryBackupRetentionDays)
    $directory = Join-Path $Root 'logs\registry-backup'
    if (-not (Test-Path -LiteralPath $directory)) { return 0 }
    $cutoff = [datetime]::UtcNow.AddDays(-$RetentionDays)
    $orphanCutoff = [datetime]::UtcNow.AddDays(-1)
    $deleted = 0
    $gone = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction SilentlyContinue) {
        if ($gone.Contains($f.FullName)) { continue }
        if ($f.Extension -ieq '.json') {
            if (Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($f.FullName, '.reg')) -PathType Leaf) { continue }
            if ($f.LastWriteTimeUtc -lt $orphanCutoff -and (Remove-CleanupFile $f)) { $deleted++ }
            continue
        }
        if ($f.LastWriteTimeUtc -ge $cutoff) { continue }
        if (-not (Remove-CleanupFile $f)) { continue }   # gesperrt: Paar bleibt ganz
        $deleted++
        if ($f.Extension -ieq '.reg') {
            $sidecar = Get-Item -LiteralPath ([System.IO.Path]::ChangeExtension($f.FullName, '.json')) -ErrorAction SilentlyContinue
            if ($sidecar -and (Remove-CleanupFile $sidecar)) { $deleted++; $null = $gone.Add($sidecar.FullName) }
        }
    }
    $deleted
}
