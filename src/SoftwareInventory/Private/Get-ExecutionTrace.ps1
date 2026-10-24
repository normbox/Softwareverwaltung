# Ausführungsspuren, die ohne Administratorrechte lesbar sind. Jede Funktion liefert
# Objekte mit Path, Evidence und optional LastRun/RunCount.

function New-ExecutionTrace {
    param([string] $Path, [string] $Evidence, $LastRun = $null, $RunCount = $null)
    [pscustomobject] @{ Path = $Path; Evidence = $Evidence; LastRun = $LastRun; RunCount = $RunCount }
}

function Get-UserAssistTrace {
    <#
    .SYNOPSIS
        Per Explorer gestartete Programme des aktuellen Benutzers (UserAssist, ROT13-kodiert).
    #>
    [CmdletBinding()]
    param(
        # Schlüssel für ausführbare Dateien; der zweite UserAssist-Schlüssel enthält nur Verknüpfungen.
        [string] $Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist\{CEBFF5CD-ACE2-4F4F-9178-9926F41749EA}\Count'
    )

    if (-not (Test-Path -LiteralPath $Path)) { return }
    $key = Get-Item -LiteralPath $Path
    $folders = Get-KnownFolderMap

    foreach ($valueName in $key.GetValueNames()) {
        $decoded = ConvertFrom-Rot13 $valueName
        $file = Resolve-KnownFolderPath -Path $decoded -Map $folders
        if (-not $file -or $file -notmatch '\.exe$') { continue }

        $data = $key.GetValue($valueName)
        $info = ConvertFrom-UserAssistData $data
        New-ExecutionTrace -Path $file -Evidence UserAssist -LastRun $info.LastRun -RunCount $info.RunCount
    }
}

function ConvertFrom-Rot13 {
    param([string] $Text)
    $chars = foreach ($c in $Text.ToCharArray()) {
        if ($c -cmatch '[a-z]') { [char] ((([int] $c - 97 + 13) % 26) + 97) }
        elseif ($c -cmatch '[A-Z]') { [char] ((([int] $c - 65 + 13) % 26) + 65) }
        else { $c }
    }
    -join $chars
}

function ConvertFrom-UserAssistData {
    # Ab Windows 7: 72 Byte, Startanzahl ab Byte 4, letzter Start (FILETIME) ab Byte 60.
    param([byte[]] $Data)
    $result = @{ RunCount = $null; LastRun = $null }
    if ($null -eq $Data -or $Data.Length -lt 68) { return $result }
    $count = [BitConverter]::ToInt32($Data, 4)
    $fileTime = [BitConverter]::ToInt64($Data, 60)
    if ($count -gt 0) { $result.RunCount = $count }
    if ($fileTime -gt 0) { $result.LastRun = [datetime]::FromFileTimeUtc($fileTime).ToString('o') }
    $result
}

function Get-KnownFolderMap {
    # UserAssist speichert Pfade teils als {KnownFolderID}\datei.exe.
    $shellFolders = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $downloads = (Get-ItemProperty -LiteralPath $shellFolders -ErrorAction SilentlyContinue).'{374DE290-123F-4565-9164-39C4925E467B}'
    @{
        '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}' = [Environment]::SystemDirectory
        '{D65231B0-B2F1-4857-A4CE-A8E7C6EA7D27}' = [Environment]::GetFolderPath('SystemX86')
        '{F38BF404-1D43-42F2-9305-67DE0B28FC23}' = [Environment]::GetFolderPath('Windows')
        '{6D809377-6AF0-444B-8957-A3773F02200E}' = [Environment]::GetFolderPath('ProgramFiles')
        '{7C5A40EF-A0FB-4BFC-874A-C0F2E0B9FA8E}' = [Environment]::GetFolderPath('ProgramFilesX86')
        '{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}' = [Environment]::GetFolderPath('Desktop')
        '{FDD39AD0-238F-46AF-ADB4-6C85480369C7}' = [Environment]::GetFolderPath('MyDocuments')
        '{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}' = [Environment]::GetFolderPath('LocalApplicationData')
        '{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}' = [Environment]::GetFolderPath('ApplicationData')
        '{5E6C858F-0E22-4760-9AFE-EA3317B67173}' = [Environment]::GetFolderPath('UserProfile')
        '{374DE290-123F-4565-9164-39C4925E467B}' = if ($downloads) { [Environment]::ExpandEnvironmentVariables($downloads) } else { Join-Path $env:USERPROFILE 'Downloads' }
    }
}

function Resolve-KnownFolderPath {
    param([string] $Path, [hashtable] $Map)
    if ($Path -match '^(?<id>\{[0-9A-Fa-f-]{36}\})\\(?<rest>.+)$') {
        $base = $Map[$Matches.id.ToUpperInvariant()]
        if ($base) { return Join-Path $base $Matches.rest }
        return $null
    }
    if ($Path -match '^[A-Za-z]:\\') { return $Path }
    $null
}

function Get-ProcessTrace {
    # Laufende Prozesse des aktuellen Benutzers (fremde Prozesse liefern ohne Admin keinen Pfad).
    [CmdletBinding()]
    param()
    Get-Process -ErrorAction SilentlyContinue | Where-Object Path | Select-Object -ExpandProperty Path -Unique |
        ForEach-Object { New-ExecutionTrace -Path $_ -Evidence Process }
}

function Get-AutostartTrace {
    # Run-/RunOnce-Schlüssel und Autostart-Ordner.
    [CmdletBinding()]
    param()

    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    foreach ($keyPath in $runKeys) {
        if (-not (Test-Path -LiteralPath $keyPath)) { continue }
        $key = Get-Item -LiteralPath $keyPath
        foreach ($name in $key.GetValueNames()) {
            $exe = ConvertFrom-CommandLine ([string] $key.GetValue($name))
            if ($exe) { New-ExecutionTrace -Path $exe -Evidence Autostart }
        }
    }

    $shell = $null
    foreach ($folder in [Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) {
        if (-not $folder -or -not (Test-Path -LiteralPath $folder)) { continue }
        foreach ($item in Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue) {
            $target = switch ($item.Extension) {
                '.exe' { $item.FullName }
                '.lnk' {
                    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
                    $shell.CreateShortcut($item.FullName).TargetPath
                }
            }
            if ($target -match '\.exe$') { New-ExecutionTrace -Path $target -Evidence Autostart }
        }
    }
}

function Get-ScheduledTaskTrace {
    # Geplante Aufgaben außerhalb von \Microsoft\, soweit für den Benutzer sichtbar.
    [CmdletBinding()]
    param()
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object TaskPath -notlike '\Microsoft\*'
    foreach ($task in $tasks) {
        foreach ($action in @($task.Actions)) {
            if (-not $action.PSObject.Properties['Execute'] -or -not $action.Execute) { continue }
            $exe = ConvertFrom-CommandLine $action.Execute
            if ($exe) { New-ExecutionTrace -Path $exe -Evidence ScheduledTask }
        }
    }
}

function ConvertFrom-CommandLine {
    <#
    .SYNOPSIS
        Ermittelt den Pfad der .exe aus einer Befehlszeile; Umgebungsvariablen werden aufgelöst.
    #>
    param([string] $CommandLine)
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $text = [Environment]::ExpandEnvironmentVariables($CommandLine.Trim())

    $path = if ($text -match '^"(?<p>[^"]+)"') { $Matches.p }
    elseif ($text -match '^(?<p>.+?\.exe)(\s|$)') { $Matches.p }
    else { ($text -split '\s+')[0] }

    if ($path -match '^[A-Za-z]:\\.+\.exe$') { $path } else { $null }
}
