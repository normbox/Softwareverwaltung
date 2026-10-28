# Befehlszeilen aus der Registry (UninstallString, QuietUninstallString) sicher zerlegen.
# Grundsatz: nie über eine Shell ausführen (kein cmd /c, kein Invoke-Expression). Der Programmpfad
# wird herausgelöst, der Rest bleibt unverändert als Argumentzeichenfolge, so wie der Hersteller
# ihn eingetragen hat. Skript-Interpreter werden abgelehnt.

$script:BlockedInterpreter = @(
    'cmd.exe', 'powershell.exe', 'pwsh.exe', 'powershell_ise.exe', 'wscript.exe', 'cscript.exe',
    'mshta.exe', 'rundll32.exe', 'regsvr32.exe', 'bash.exe', 'wsl.exe', 'conhost.exe'
)

function Split-CommandLine {
    <#
    .SYNOPSIS
        Zerlegt eine Befehlszeile in Programmpfad und Argumente.
    .DESCRIPTION
        "C:\Pfad mit Leerzeichen\unins000.exe" /SILENT  -> Pfad in Anführungszeichen
        C:\Program Files\App\uninst.exe /S              -> längster vorhandener .exe-Präfix
        MsiExec.exe /X{GUID}                            -> Programmname ohne Pfad, aus System32
        Umgebungsvariablen im Pfad werden aufgelöst, in den Argumenten nicht.
    .OUTPUTS
        @{ FilePath; Arguments; Error } – Error ist gesetzt, wenn sich kein Programm bestimmen lässt.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $CommandLine)

    $text = if ($CommandLine) { $CommandLine.Trim() } else { '' }
    if (-not $text) { return @{ FilePath = $null; Arguments = $null; Error = (New-InventoryMessage CommandEmpty) } }

    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        if ($end -lt 2) { return @{ FilePath = $null; Arguments = $null; Error = (New-InventoryMessage CommandUnclosedQuote) } }
        $path = [Environment]::ExpandEnvironmentVariables($text.Substring(1, $end - 1))
        return @{ FilePath = $path; Arguments = $text.Substring($end + 1).Trim(); Error = $null }
    }

    # Ohne Anführungszeichen: Kandidaten sind alle Präfixe, die an einem Leerzeichen enden
    # und auf .exe enden. Der erste vorhandene gewinnt; sonst der erste Kandidat überhaupt.
    $candidates = [System.Collections.Generic.List[int]]::new()
    $index = 0
    while ($index -ge 0) {
        $index = $text.IndexOf(' ', $index + 1)
        $cut = if ($index -lt 0) { $text.Length } else { $index }
        if ($text.Substring(0, $cut).EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { $candidates.Add($cut) }
    }
    if (-not $candidates.Count) { return @{ FilePath = $null; Arguments = $null; Error = (New-InventoryMessage CommandNoExe) } }

    $chosen = $candidates[0]
    foreach ($cut in $candidates) {
        $candidate = Resolve-CommandPath ([Environment]::ExpandEnvironmentVariables($text.Substring(0, $cut)))
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $chosen = $cut; break }
    }
    @{
        FilePath  = Resolve-CommandPath ([Environment]::ExpandEnvironmentVariables($text.Substring(0, $chosen)))
        Arguments = $text.Substring($chosen).Trim()
        Error     = $null
    }
}

function Resolve-CommandPath {
    # Programmname ohne Ordner (MsiExec.exe) wird nur in System32 gesucht, nie über PATH.
    param([string] $Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    Join-Path ([Environment]::GetFolderPath('System')) $Path
}

function Resolve-UninstallCommand {
    <#
    .SYNOPSIS
        Zerlegt und prüft einen Deinstallationsbefehl aus der Registry.
    .OUTPUTS
        @{ FilePath; Arguments; Error }
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $CommandLine)

    $parts = Split-CommandLine $CommandLine
    if ($parts.Error) { return $parts }
    $name = [System.IO.Path]::GetFileName($parts.FilePath)
    if ($name -in $script:BlockedInterpreter) {
        $parts.Error = New-InventoryMessage CommandInterpreter $name
        return $parts
    }
    if (-not (Test-Path -LiteralPath $parts.FilePath -PathType Leaf)) {
        $parts.Error = New-InventoryMessage CommandFileNotFound $parts.FilePath
    }
    $parts
}

function Format-CommandLine {
    # Nur zur Anzeige und fürs Protokoll; ausgeführt wird immer FilePath + Arguments.
    param([string] $FilePath, [string] $Arguments)
    $quoted = if ($FilePath -match '\s') { "`"$FilePath`"" } else { $FilePath }
    if ($Arguments) { "$quoted $Arguments" } else { $quoted }
}

function Test-PrivilegedSid {
    # Administratoren, SYSTEM und TrustedInstaller: Wer diese Rechte hat, braucht keinen Umweg über eine Datei.
    param([string] $Sid)
    $Sid -in 'S-1-5-32-544', 'S-1-5-18', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
}

function Test-UserWritablePath {
    <#
    .SYNOPSIS
        Kann der aktuelle Benutzer (ohne Adminrechte) die Datei oder ihren Ordner verändern?
    .DESCRIPTION
        Eine solche Datei darf nie mit Administratorrechten gestartet werden, sonst könnte
        Schadsoftware sie vorher austauschen. Geprüft werden typische Benutzerorte und die ACL
        von Datei und Ordner. Im Zweifel gilt der Pfad als beschreibbar.
    #>
    param([Parameter(Mandatory)] [string] $Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $userRoots = @($env:USERPROFILE, $env:TEMP, $env:TMP, $env:PUBLIC, $env:LOCALAPPDATA, $env:APPDATA) |
        Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') + '\' }
    foreach ($root in $userRoots) {
        if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    # Groups enthält nur aktive Gruppen; im Token ohne Adminrechte zählt „Administratoren“ also nicht.
    # Läuft die App bereits erhöht (z. B. UAC aus), sind die Gruppen aktiv. Schreibrechte dieser
    # Konten sind aber keine Gefahr, sonst gälte jede Datei unter „Programme“ als beschreibbar.
    $sids = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($sid in @($identity.User.Value) + @($identity.Groups | ForEach-Object Value)) {
        if (-not (Test-PrivilegedSid $sid)) { [void] $sids.Add($sid) }
    }

    $write = [System.Security.AccessControl.FileSystemRights] 'WriteData, AppendData, WriteAttributes, WriteExtendedAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership'
    foreach ($target in @($full, [System.IO.Path]::GetDirectoryName($full))) {
        if (-not $target -or -not (Test-Path -LiteralPath $target)) { continue }
        try {
            $acl = Get-Acl -LiteralPath $target -ErrorAction Stop
        }
        catch {
            return $true
        }
        foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne 'Allow') { continue }
            if (-not $sids.Contains($rule.IdentityReference.Value)) { continue }
            # Nur-Vererbung (InheritOnly) gilt nicht für das Objekt selbst.
            if ($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
            if ($rule.FileSystemRights -band $write) { return $true }
        }
    }
    $false
}
