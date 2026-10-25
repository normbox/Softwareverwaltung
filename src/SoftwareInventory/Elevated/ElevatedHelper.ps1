<#
.SYNOPSIS
    Helfer, der genau eine Aktion mit Administratorrechten ausführt.
.DESCRIPTION
    Wird vom Modul über Start-ElevatedHelper in einem eigenen, per UAC erhöhten Prozess gestartet.
    Läuft unter Windows PowerShell 5.1 (immer vorhanden) und unter PowerShell 7; deshalb nur
    Sprachmittel von 5.1 verwenden. Der Helfer trifft keine Entscheidungen: Programm, Argumente und
    Optionen kommen fertig geprüft aus dem Plan (New-ActionPlan). Er
      1. legt auf Wunsch einen Wiederherstellungspunkt an,
      2. prüft die Programmdatei erneut und startet sie ohne Shell,
      3. meldet Exit-Code, Ausgabe und ggf. MSI-Log über die Named Pipe des Aufrufers zurück.
    Er schreibt nichts in den Benutzerordner; ein MSI-Log entsteht im Temp-Ordner des erhöhten
    Kontexts und wird nach dem Auslesen gelöscht.
    Ohne -PlanBase64 werden nur die Funktionen definiert (für Tests).
#>
param(
    [string] $PlanBase64
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function New-HelperResult {
    param($Plan)
    [ordered]@{
        Nonce               = $Plan.Nonce
        HelperVersion       = 1
        PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
        RestorePoint        = 'NotRequested'
        RestorePointMessage = $null
        Started             = $false
        ExitCode            = $null
        TimedOut            = $false
        Output              = $null
        InstallerLog        = $null
        Error               = $null
    }
}

function Get-LatestRestorePointSequence {
    $points = @(Get-CimInstance -Namespace 'root/default' -ClassName 'SystemRestore' -ErrorAction Stop)
    if ($points.Count -eq 0) { return 0 }
    [long] (($points | Measure-Object -Property SequenceNumber -Maximum).Maximum)
}

function Test-SystemProtectionDisabled {
    # RPSessionInterval = 0 bedeutet: Computerschutz ist ausgeschaltet. Fehlt der Wert, gilt „unbekannt“.
    try {
        $value = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'RPSessionInterval' -ErrorAction Stop).RPSessionInterval
        return ($value -eq 0)
    }
    catch {
        return $false
    }
}

function Invoke-RestorePoint {
    <#
    .SYNOPSIS
        Legt einen Wiederherstellungspunkt an und meldet ehrlich, was passiert ist.
    .OUTPUTS
        @{ Status = Created|Skipped|NotAvailable|Failed; Message }
    #>
    param([string] $Description, [uint32] $Type)

    try {
        $before = Get-LatestRestorePointSequence
    }
    catch {
        return @{ Status = 'NotAvailable'; Message = "Systemwiederherstellung nicht verfügbar: $($_.Exception.Message)" }
    }

    try {
        $arguments = @{ Description = $Description; RestorePointType = $Type; EventType = [uint32] 100 }
        $call = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'CreateRestorePoint' -Arguments $arguments -ErrorAction Stop
        $code = [long] $call.ReturnValue
    }
    catch {
        return @{ Status = 'Failed'; Message = "Wiederherstellungspunkt fehlgeschlagen: $($_.Exception.Message)" }
    }

    if ($code -eq 1058 -or $code -eq 1068 -or $code -eq -2147023838) {
        return @{ Status = 'NotAvailable'; Message = 'Computerschutz ist ausgeschaltet oder der Dienst deaktiviert' }
    }
    if ($code -ne 0) {
        return @{ Status = 'Failed'; Message = "Wiederherstellungspunkt fehlgeschlagen (Code $code)" }
    }

    $after = $before
    try { $after = Get-LatestRestorePointSequence } catch { $after = $before }
    if ($after -gt $before) { return @{ Status = 'Created'; Message = "Wiederherstellungspunkt angelegt (Nr. $after)" } }
    if (Test-SystemProtectionDisabled) {
        return @{ Status = 'NotAvailable'; Message = 'Computerschutz ist ausgeschaltet' }
    }
    @{ Status = 'Skipped'; Message = 'Windows hat keinen neuen Punkt angelegt; meist, weil in den letzten 24 Stunden schon einer angelegt wurde' }
}

function Test-HelperFilePath {
    # Letzte Prüfung im erhöhten Prozess. Die ACL-Prüfung (Test-UserWritablePath) erfolgt vorher
    # ohne Adminrechte; hier zusätzlich: keine Benutzer- oder Temp-Ordner, winget nur aus WindowsApps.
    param([string] $FilePath)
    if (-not $FilePath -or -not [System.IO.Path]::IsPathRooted($FilePath)) { return 'Programmpfad fehlt oder ist nicht absolut' }
    $full = [System.IO.Path]::GetFullPath($FilePath)
    if ([System.IO.Path]::GetFileName($full) -ieq 'winget.exe') {
        $apps = (Join-Path $env:ProgramFiles 'WindowsApps').TrimEnd('\') + '\'
        if (-not $full.StartsWith($apps, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return "winget wurde im Administratorkontext nicht gefunden ($full)"
        }
        return $null
    }
    $blocked = @((Join-Path $env:SystemDrive 'Users'), (Join-Path $env:windir 'Temp'), [System.IO.Path]::GetTempPath()) |
        ForEach-Object { $_.TrimEnd('\') + '\' }
    foreach ($root in $blocked) {
        if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return "Programm liegt in einem Benutzer- oder Temp-Ordner ($full)" }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return "Programmdatei nicht gefunden: $full" }
    $null
}

function Get-OutputTail {
    # Letzte Zeilen ohne Fortschrittsanzeigen (winget zeichnet Balken und Drehstriche mit \r).
    param([string] $Text, [int] $Lines = 50)
    if (-not $Text) { return $null }
    $clean = foreach ($line in ($Text -split "`r`n|`n")) {
        $last = ($line -split "`r" | Where-Object { $_.Trim() } | Select-Object -Last 1)
        if (-not $last) { continue }
        $t = $last.TrimEnd()
        if ($t -match '^[\s\-\\|/█▒]*$' -or $t -match '^\s*[█▒]+\s') { continue }
        $t
    }
    (@($clean) | Select-Object -Last $Lines) -join "`n"
}

function Invoke-HelperProcess {
    <#
    .SYNOPSIS
        Startet das Programm ohne Shell und wartet höchstens TimeoutSeconds.
    #>
    param($Plan, $Result)

    $arguments = [string] $Plan.Arguments
    $logPath = $null
    if ($Plan.MsiLog) {
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("SoftwareInventory-" + $Plan.Nonce + '.log')
        $arguments = ($arguments + ' /l*v "' + $logPath + '"').Trim()
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Plan.FilePath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    try {
        $process = [System.Diagnostics.Process]::Start($psi)
        $Result.Started = $true
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($process.WaitForExit([int] $Plan.TimeoutSeconds * 1000)) {
            $process.WaitForExit()
            $Result.ExitCode = $process.ExitCode
            $Result.Output = Get-OutputTail ($stdout.Result + "`n" + $stderr.Result)
        }
        else {
            # Nicht beenden: ein halb abgebrochenes Deinstallationsprogramm ist schlimmer.
            $Result.TimedOut = $true
        }
    }
    finally {
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            try { $Result.InstallerLog = Get-OutputTail ([System.IO.File]::ReadAllText($logPath)) 2000 } catch { $Result.InstallerLog = $null }
            Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Send-HelperResult {
    param([string] $PipeName, $Result)
    $json = ConvertTo-Json -InputObject ([pscustomobject] $Result) -Depth 4 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName, [System.IO.Pipes.PipeDirection]::Out)
    try {
        $pipe.Connect(30000)
        $pipe.Write($bytes, 0, $bytes.Length)
        $pipe.Flush()
        $pipe.WaitForPipeDrain()
    }
    finally {
        $pipe.Dispose()
    }
}

function Invoke-ElevatedHelperMain {
    param([string] $PlanBase64)
    $plan = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PlanBase64)) | ConvertFrom-Json
    $result = New-HelperResult $plan
    try {
        if ($plan.RestorePoint) {
            $rp = Invoke-RestorePoint -Description $plan.RestorePointDescription -Type ([uint32] $plan.RestorePointType)
            $result.RestorePoint = $rp.Status
            $result.RestorePointMessage = $rp.Message
        }
        if ($plan.FilePath) {
            $problem = Test-HelperFilePath $plan.FilePath
            if ($problem) { $result.Error = $problem }
            else { Invoke-HelperProcess -Plan $plan -Result $result }
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }
    Send-HelperResult -PipeName $plan.PipeName -Result $result
}

if ($PlanBase64) {
    try {
        Invoke-ElevatedHelperMain -PlanBase64 $PlanBase64
        exit 0
    }
    catch {
        exit 1
    }
}
