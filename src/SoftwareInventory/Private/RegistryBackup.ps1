# Sicherung von Registry-Schlüsseln vor dem Entfernen verwaister Einträge (Remove-OrphanedEntry).
# Liegt unter logs\registry-backup\ und hat eine eigene Frist (365 Tage), unabhängig von der normalen
# Selbstbereinigung und nicht in deren Größengrenze. Je Sicherung gibt es zwei Dateien mit gleichem Namen:
# <ActionId>_<Name>.reg (reg export) und <ActionId>_<Name>.json (Angaben zur Sicherung, nur Codes, nie Text).

$script:RegistryBackupRetentionDays = 365
$script:RegistryBackupMaxBytes = 16MB
$script:RegistryBackupSidecarMaxBytes = 64KB
# Nur diese Gründe übernimmt das Modul in die Begleitdatei, je Code mit genau dieser Zahl Argumente; alles andere wird
# verworfen. Die Zahl hängt bewusst nicht am Anzeigetext (psd1, spätere Übersetzungen), damit ein geänderter Text nie
# gespeicherte Sicherungen ungültig macht. Dieselbe Tabelle steht im Helfer (RegistryRemoval.KnownReasonArgCounts);
# beide prüfen gegen tests/Data/backup-reason-cases.json.
$script:KnownBackupReasonCodes = @{ OrphanedEntry = 0; NewerInstallNextTo = 2 }
# Ungewöhnliche Zeilenumbrüche: NUL, VT, FF, NEL, U+2028, U+2029 sowie einzelnes CR oder LF. Die Zeichen stehen als
# Codepunkte, nie als Escape-Text im Quelltext (CLAUDE.md).
$script:OddLineBreakPattern = '[' + (-join (0x00, 0x0B, 0x0C, 0x85, 0x2028, 0x2029 | ForEach-Object { '\u{0:X4}' -f $_ })) + ']|\r(?!\n)|(?<!\r)\n'
# Unsichere Zeichen in einem Schlüsselnamen: [, ] und " sowie Steuerzeichen (U+0000-U+001F, U+007F-U+009F). Ebenfalls aus
# Codepunkten gebaut; Modul und Helfer lehnen solche Schlüssel ab (KeyNameUnsafe), sie bleiben Handarbeit.
$script:UnsafeKeyNamePattern = '[\[\]"' + (-join ((0x00, 0x1F), (0x7F, 0x9F) | ForEach-Object { '\u{0:X4}-\u{1:X4}' -f $_[0], $_[1] })) + ']'

function Get-RegistryBackupDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\registry-backup'
}

function Get-RegistryBackupMachineDirectory {
    # HKLM-Sicherungen legt nur der erhöhte Helfer an, im Admin-Ordner (BackupFolderRules.FolderPath im Helfer).
    Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Softwareverwaltung\RegistryBackup'
}

function Test-MachineRegistryKeyPresent {
    <#
    .SYNOPSIS
        Gibt es den HKLM-Schlüssel? In der 64-Bit-Ansicht wie der Helfer (WOW6432Node als wörtlicher Pfad).
    .DESCRIPTION
        Unabhängig von der Bitness des Prozesses: Ein 32-Bit-Prozess sähe über HKLM:\ sonst die umgeleitete Ansicht und
        könnte einen Schlüssel für „weg“ halten, den der Helfer gar nicht gelöscht hat (oder umgekehrt).
    #>
    param([Parameter(Mandatory)] [string] $RegistryKey)
    # Fail-closed: Ohne HKLM-Präfix ließe sich „weg“ nicht beurteilen (OpenSubKey liefert sonst einfach $null).
    if ($RegistryKey -notmatch '^(?i:HKLM:\\|HKEY_LOCAL_MACHINE\\).') { throw [System.ArgumentException]::new("Kein HKLM-Schlüssel: $RegistryKey") }
    $sub = $RegistryKey -replace '^(?i:HKLM:\\|HKEY_LOCAL_MACHINE\\)', ''
    $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key = $root.OpenSubKey($sub, $false)
        try { $null -ne $key } finally { if ($key) { $key.Dispose() } }
    }
    finally { $root.Dispose() }
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
    # Die Kennung einer Sicherung ist die ActionId (GUID) am Anfang des Dateinamens: <Id>_<Name>.reg (HKCU) oder genau
    # <Id>.reg bzw. <Id>.json (HKLM, vom Helfer); sonst $null. <Id>.import.reg (Zwischendatei des Helfers) ist keine Sicherung.
    param([string] $File)
    $name = [System.IO.Path]::GetFileName($File)
    if ($name -match '^(?<id>[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:_|\.(?:reg|json)\z)') { $Matches.id.ToLowerInvariant() }
}

function Get-RegistryBackupFile {
    <#
    .SYNOPSIS
        Alle Sicherungsdateien (.reg) beider Orte mit ihrem Bereich (Eigenschaft BackupScope).
    .DESCRIPTION
        User: logs\registry-backup (<Id>_<Name>.reg). Machine: der Admin-Ordner unter Program Files, nur Dateien genau
        <Id>.reg, keine Links. Nur lesend; der Admin-Ordner ist für Benutzer lesbar. Ist er nicht lesbar, fehlen seine
        Sicherungen hier (Get-RegistryBackupStatus meldet das).
    #>
    $places = @(
        @{ Path = (Get-RegistryBackupDirectory); Scope = 'User' }
        @{ Path = (Get-RegistryBackupMachineDirectory); Scope = 'Machine' }
    )
    foreach ($place in $places) {
        if (-not (Test-Path -LiteralPath $place.Path -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $place.Path -File -Force -ErrorAction SilentlyContinue) {
            if ($file.Extension -ine '.reg' -or -not (Get-RegistryBackupId $file.Name)) { continue }
            if ($place.Scope -eq 'Machine' -and ($file.Name -notmatch '^[0-9a-fA-F-]{36}\.reg\z' -or ($file.Attributes -band [System.IO.FileAttributes]::ReparsePoint))) { continue }
            $file | Add-Member -NotePropertyName BackupScope -NotePropertyValue $place.Scope -Force -PassThru
        }
    }
}

function Test-RegistryBackupExpired {
    # Älter als die Frist (365 Tage) nach der Änderungszeit der .reg, wie die Bereinigung in Modul und Helfer.
    param([System.IO.FileInfo] $File)
    $File.LastWriteTimeUtc -lt [datetime]::UtcNow.AddDays(-$script:RegistryBackupRetentionDays)
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
    ConvertFrom-RegistryBackupByte -Bytes ([System.IO.File]::ReadAllBytes($File))
}

function ConvertFrom-RegistryBackupByte {
    <#
    .SYNOPSIS
        Prüft die Bytes einer .reg-Sicherung und liest daraus den Text.
    .DESCRIPTION
        Dieselben Regeln wie BackupFileRules.DecodeText im Helfer (gemeinsame Tabelle
        tests/Data/registry-backup-cases.json, fileCases): leer, zu groß (über 16 MB), und UTF-16 Little Endian mit der
        Bytefolge FF FE am Anfang und gerader Anzahl Bytes danach, wie reg export sie schreibt.
    .OUTPUTS
        @{ Problem; Bytes; Text } (Problem $null, wenn alles passt; sonst Empty, TooLarge oder BadEncoding).
    #>
    param($Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return @{ Problem = 'Empty'; Bytes = $null; Text = $null } }
    if ($Bytes.Length -gt $script:RegistryBackupMaxBytes) { return @{ Problem = 'TooLarge'; Bytes = $null; Text = $null } }
    if ($Bytes.Length -lt 2 -or $Bytes[0] -ne 0xFF -or $Bytes[1] -ne 0xFE -or (($Bytes.Length - 2) % 2) -ne 0) {
        return @{ Problem = 'BadEncoding'; Bytes = $null; Text = $null }
    }
    @{ Problem = $null; Bytes = $Bytes; Text = [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2) }
}

function Get-RegistryValueData {
    # Daten einer Wertzeile (alles nach dem = hinter dem Namen); $null ohne vollständigen Namen mit =.
    # Name: @ oder "..." mit \" und \\ als Escape. Dieselbe Zerlegung wie RegistryBackupRules.ValueData im Helfer.
    param([string] $Line)
    $index = 1
    if ($Line[0] -cne '@') {
        while ($index -lt $Line.Length -and $Line[$index] -cne '"') { $index += $(if ($Line[$index] -ceq '\') { 2 } else { 1 }) }
        if ($index -ge $Line.Length) { return $null }
        $index++
    }
    while ($index -lt $Line.Length -and ($Line[$index] -ceq ' ' -or $Line[$index] -ceq "`t")) { $index++ }
    if ($index -lt $Line.Length -and $Line[$index] -ceq '=') { return $Line.Substring($index + 1) }
    $null
}

function Test-RegistryBackupContent {
    <#
    .SYNOPSIS
        Prüft den Inhalt einer .reg-Sicherung streng, bevor sie zurückgespielt wird.
    .DESCRIPTION
        Erlaubt ist genau ein Hauptschlüssel (der Schlüssel aus der Begleitdatei) direkt unter einem
        Uninstall-Zweig des erlaubten Bereichs (-Scope, Vorgabe User); jeder weitere Schlüsselkopf muss mit "<Hauptschlüssel>\" beginnen
        (Unterschlüssel). Keine Löschzeilen ([-...] für Schlüssel, "Name"=- und @=- für Werte), keine anderen Schlüssel, nur bekannte Zeilenformate (Wert,
        Kommentar, Hex-Fortsetzung; sonst BadLine).
    .OUTPUTS
        $null, wenn der Inhalt passt; sonst der Grund: Empty, BadLineBreak, BadHeader, BadLine, DeleteLine, BadKeyLine, KeyNameUnsafe, KeyNotFound,
        KeyMismatch, KeyOutside, KeyNotUninstall, MachineKeyInUserBackup (HKLM, aber nur User erlaubt) oder WrongScope
        (HKCU, aber nur Machine erlaubt). Der Helfer prüft mit denselben Regeln (RegistryBackupRules.cs); beide
        gegen tests/Data/registry-backup-cases.json.
    #>
    param([string] $Text, [string] $NativeKey, [ValidateSet('User', 'Machine')] [string] $Scope = 'User')
    if (-not $Text -or -not $NativeKey) { return 'Empty' }
    # reg export schreibt nur CRLF. Einzelne CR/LF, NUL oder andere Zeilentrenner lehnen wir ab: Würde reg.exe
    # dort anders trennen als diese Prüfung, könnte sich eine Schlüsselzeile an der Prüfung vorbeischmuggeln.
    if ($Text -match $script:OddLineBreakPattern) { return 'BadLineBreak' }
    $lines = $Text -split "\r\n"
    $blanks = [char[]] @(' ', "`t")
    if (-not [string]::Equals($lines[0].TrimEnd($blanks), 'Windows Registry Editor Version 5.00', [StringComparison]::Ordinal)) { return 'BadHeader' }

    $headers = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines | Select-Object -Skip 1) {
        # Nur Leerzeichen und Tabulator werden abgeschnitten (nicht von der Laufzeit abhängig): Eine Zeile mit einem
        # anderen führenden Zeichen, auch unsichtbaren wie U+00AD oder U+200B, ist kein bekanntes Format.
        $t = $line.Trim($blanks)
        if ($t.Length -eq 0) { continue }
        if (-not $t.StartsWith('[', [StringComparison]::Ordinal)) {
            # Wertzeilen ("Name"=..., @=...): Name zerlegen; beginnen die Daten mit - ("Name"=-, @=-, auch mit Kommentar
            # dahinter), löscht reg import einen Wert: wie [-...] abgelehnt. Ohne vollständigen Namen mit = unbekannt.
            if ($t[0] -ceq '"' -or $t[0] -ceq '@') {
                $data = Get-RegistryValueData $t
                if ($null -eq $data) { return 'BadLine' }
                if ($data.TrimStart($blanks).StartsWith('-', [StringComparison]::Ordinal)) { return 'DeleteLine' }
                continue
            }
            # Kommentare und Hex-Fortsetzungen; alles andere ist unbekannt.
            if ($t[0] -ceq ';' -or $t -cmatch '^[0-9A-Fa-f]{2}(,[0-9A-Fa-f]{2})*,?\\?$') { continue }
            return 'BadLine'
        }
        if ($t.StartsWith('[-', [StringComparison]::Ordinal)) { return 'DeleteLine' }
        if ($t.Length -lt 3 -or -not $t.EndsWith(']', [StringComparison]::Ordinal)) { return 'BadKeyLine' }
        $name = $t.Substring(1, $t.Length - 2)
        # [ oder ] oder ein Steuerzeichen (U+0000-U+001F, U+007F, U+0080-U+009F) im Namen: nie sicher zu lesen, Handarbeit.
        if ($name -cmatch $script:UnsafeKeyNamePattern) { return 'KeyNameUnsafe' }
        $headers.Add($name)
    }
    if ($headers.Count -eq 0) { return 'KeyNotFound' }
    if (-not [string]::Equals($headers[0], $NativeKey, [StringComparison]::OrdinalIgnoreCase)) { return 'KeyMismatch' }
    # Ein Hauptschlüssel mit \ am Ende oder leerer Komponente (\\) wäre der Zweig selbst: Der Präfix ließe dann jeden
    # Schlüssel darunter zu.
    if ($NativeKey.EndsWith('\', [StringComparison]::Ordinal) -or $NativeKey.Contains('\\')) { return 'KeyNotUninstall' }
    $prefix = $NativeKey + '\'
    for ($i = 1; $i -lt $headers.Count; $i++) {
        $h = $headers[$i]
        if (-not $h.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or $h.EndsWith('\', [StringComparison]::Ordinal) -or $h.Contains('\\')) { return 'KeyOutside' }
    }

    $cut = $NativeKey.LastIndexOf('\')
    if ($cut -lt 1) { return 'KeyNotUninstall' }
    $parent = $NativeKey.Substring(0, $cut)
    $location = Get-UninstallLocationNative | Where-Object { [string]::Equals($_.NativePath, $parent, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if (-not $location) { return 'KeyNotUninstall' }
    if ($location.Scope -ne $Scope) { return $(if ($location.Scope -eq 'Machine') { 'MachineKeyInUserBackup' } else { 'WrongScope' }) }
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

function Get-BackupReasonPart {
    # Code (Zeichenkette) und Args (ohne $null) eines Grundes. Gründe sind Objekte (Meldungen, aus JSON) oder
    # Dictionaries (aus dem Plan).
    param($Reason)
    $field = { param($n) if ($Reason -is [System.Collections.IDictionary]) { if ($Reason.Contains($n)) { $Reason[$n] } } else { Get-RecordValue $Reason $n } }
    @{ Code = [string] (& $field 'Code'); Args = @(@(& $field 'Args') | Where-Object { $null -ne $_ }) }
}

function Test-KnownBackupReason {
    # Bekannter Code (genaue Schreibweise) mit genau der festen Zahl Argumente aus $script:KnownBackupReasonCodes.
    # $null-Argumente zählen nicht mit.
    param([string] $Code, [object[]] $Arguments = @())
    if ($Code -cnotin @($script:KnownBackupReasonCodes.Keys)) { return $false }
    @($Arguments | Where-Object { $null -ne $_ }).Count -eq $script:KnownBackupReasonCodes[$Code]
}

function ConvertTo-KnownBackupReason {
    # Nur bekannte Grund-Codes mit genau ihrer Argumentzahl (Args als Texte, je höchstens 200 Zeichen); alles andere
    # wird verworfen, damit nie eine Sicherung entsteht, die beim Lesen als ungültig gilt.
    param($Reasons)
    foreach ($reason in @($Reasons)) {
        if ($null -eq $reason) { continue }
        $part = Get-BackupReasonPart $reason
        if (-not (Test-KnownBackupReason -Code $part.Code -Arguments $part.Args)) { continue }
        $reasonArgs = @($part.Args | ForEach-Object {
                $s = [string] $_
                if ($s.Length -gt 200) { $s.Substring(0, 200) } else { $s }
            })
        [ordered]@{ Code = $part.Code; Args = $reasonArgs }
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
    .PARAMETER Strict
        Für Sicherungen im Admin-Ordner: so streng wie der Helfer (SidecarParser, ReadSidecarChecked), damit die Liste
        keine Sicherung als zurückspielbar zeigt, die der Helfer nach der UAC-Abfrage ablehnt. Gültiges UTF-8 ohne BOM;
        SchemaVersion als Ganzzahl 1 (nicht "1" oder 1.0); ActionId, Name, NativeKey und Scope als Zeichenketten;
        Feldnamen mit genauer Groß-/Kleinschreibung.
    #>
    param([string] $File, [switch] $Strict)
    $invalid = @{ Problem = 'MetadataInvalid'; Data = $null }
    $path = Get-RegistryBackupSidecarPath $File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Problem = 'MetadataMissing'; Data = $null } }
    if ((Get-Item -LiteralPath $path).Length -gt $script:RegistryBackupSidecarMaxBytes) { return $invalid }
    try {
        if ($Strict) {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return $invalid }
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            # -NoEnumerate: Ein Array um das Objekt ([ {...} ]) bleibt ein Array und wird unten abgelehnt, wie beim Helfer
            # (JavaScriptSerializer liefert dann kein Dictionary). Ohne den Schalter rollte PowerShell es zum Objekt aus.
            $d = ConvertFrom-Json -InputObject $text -NoEnumerate -ErrorAction Stop
        }
        else { $d = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop }
    }
    catch { return $invalid }
    if ($d -isnot [pscustomobject]) { return $invalid }
    if ($Strict) {
        # Feldnamen genau wie der Helfer (Dictionary mit Groß-/Kleinschreibung); Typen wie der JavaScriptSerializer sie liefert.
        $field = { param($Name) foreach ($p in $d.PSObject.Properties) { if ($p.Name -ceq $Name) { return , $p.Value } } }
        $version = & $field 'SchemaVersion'
        if (-not (($version -is [long] -or $version -is [int]) -and $version -eq 1)) { return $invalid }
        foreach ($name in 'ActionId', 'Name', 'NativeKey', 'Scope') {
            if ((& $field $name) -isnot [string]) { return $invalid }
        }
    }
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
    # Bekannter Grund mit anderer Argumentzahl als in $script:KnownBackupReasonCodes (z. B. zu wenige): Die Datei ist
    # beschädigt, denn so schreiben Modul und Helfer nie. Nie die Liste abbrechen lassen, sondern nur diese Sicherung als
    # ungültig zeigen (löschbar, nicht zurückspielbar). Geprüft wird gegen die feste Tabelle, nie gegen den Anzeigetext.
    # Unbekannte Codes (etwa von einer späteren Version) fallen wie bisher still weg.
    $rawReasons = @(Get-RecordValue $d 'Reasons')
    foreach ($raw in $rawReasons) {
        if ($null -eq $raw) { continue }
        $part = Get-BackupReasonPart $raw
        if ($part.Code -cin @($script:KnownBackupReasonCodes.Keys) -and -not (Test-KnownBackupReason -Code $part.Code -Arguments $part.Args)) {
            return @{ Problem = 'MetadataInvalid'; Data = $null }
        }
    }
    $reasons = @(ConvertTo-KnownBackupReason $rawReasons)
    @{
        Problem = $null
        Data    = [pscustomobject] @{
            ActionId = $id; Name = $name; NativeKey = $key; Scope = [string] (Get-RecordValue $d 'Scope'); CreatedAt = $createdAt
            Reasons  = $reasons
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
