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
        HelperVersion       = 2
        PowerShellVersion   = $PSVersionTable.PSVersion.ToString()
        RestorePoint        = 'NotRequested'
        RestorePointCode    = $null   # Code und Args; den Text bildet das Modul (Sprache der Oberfläche)
        RestorePointArgs    = @()
        Started             = $false
        ExitCode            = $null
        TimedOut            = $false
        Output              = $null
        InstallerLog        = $null
        ErrorCode           = $null
        ErrorArgs           = @()
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
        @{ Status = Created|Skipped|NotAvailable|Failed; Code; Args } – Code und Args für den Text im Modul
    #>
    param([string] $Description, [uint32] $Type)

    try {
        $before = Get-LatestRestorePointSequence
    }
    catch {
        return @{ Status = 'NotAvailable'; Code = 'RestorePointServiceUnavailable'; Args = @($_.Exception.Message) }
    }

    try {
        $arguments = @{ Description = $Description; RestorePointType = $Type; EventType = [uint32] 100 }
        $call = Invoke-CimMethod -Namespace 'root/default' -ClassName 'SystemRestore' -MethodName 'CreateRestorePoint' -Arguments $arguments -ErrorAction Stop
        $code = [long] $call.ReturnValue
    }
    catch {
        # Dienst deaktiviert kommt meist als Ausnahme, nicht als Rückgabewert.
        $codes = @(Get-ExceptionErrorCode $_.Exception)
        if ($codes | Where-Object { $_ -in $script:RestoreUnavailableCodes }) {
            return @{ Status = 'NotAvailable'; Code = 'RestorePointProtectionOffDetail'; Args = @($_.Exception.Message) }
        }
        $hex = ($codes | ForEach-Object { '0x{0:X8}' -f $_ }) -join ', '
        return @{ Status = 'Failed'; Code = 'RestorePointFailedDetail'; Args = @($_.Exception.Message, $hex) }
    }

    if ($code -in $script:RestoreUnavailableCodes) {
        return @{ Status = 'NotAvailable'; Code = 'RestorePointProtectionOff'; Args = @() }
    }
    if ($code -ne 0) {
        return @{ Status = 'Failed'; Code = 'RestorePointFailedCode'; Args = @($code) }
    }

    $after = $before
    try { $after = Get-LatestRestorePointSequence } catch { $after = $before }
    if ($after -gt $before) { return @{ Status = 'Created'; Code = 'RestorePointCreatedNumber'; Args = @($after) } }
    if (Test-SystemProtectionDisabled) {
        return @{ Status = 'NotAvailable'; Code = 'RestorePointProtectionDisabled'; Args = @() }
    }
    @{ Status = 'Skipped'; Code = 'RestorePointNotCreated'; Args = @() }
}

# 1058/1068 als Win32-Code und als HRESULT (0x80070422, 0x8007042C): Dienst deaktiviert bzw. Abhängigkeit fehlt.
$script:RestoreUnavailableCodes = @(1058, 1068, -2147023838, -2147023828)

function Get-ExceptionErrorCode {
    <#
    .SYNOPSIS
        Fehlercodes einer Ausnahme als vorzeichenbehaftete 32-Bit-Zahlen.
    .DESCRIPTION
        HResult, NativeErrorCode (Win32Exception) und bei CimException die Codes aus ErrorData
        (dort oft vorzeichenlos, z. B. 2147943458 statt -2147023838).
    #>
    param($Exception)
    foreach ($e in @($Exception, $Exception.InnerException) | Where-Object { $_ }) {
        $values = @($e.HResult)
        if ($e.PSObject.Properties['NativeErrorCode'] -and $e.NativeErrorCode -is [int]) { $values += $e.NativeErrorCode }
        if ($e.PSObject.Properties['ErrorData'] -and $e.ErrorData) {
            foreach ($p in $e.ErrorData.CimInstanceProperties) {
                if ($p.Name -match 'error_?Code|HResult|StatusCode' -and $null -ne $p.Value) { $values += $p.Value }
            }
        }
        foreach ($v in $values) {
            $n = 0L
            if ([long]::TryParse([string] $v, [ref] $n) -and $n -ne 0) {
                if ($n -gt [int]::MaxValue -and $n -le [uint32]::MaxValue) { $n -= 4294967296L }
                [int] $n
            }
        }
    }
}

function Test-HelperFilePath {
    # Letzte Prüfung im Helfer. Die ACL-Prüfung (Test-UserWritablePath) erfolgt vorher ohne
    # Adminrechte; hier zusätzlich: winget nur aus WindowsApps und, nur wenn erhöht wurde, keine
    # Benutzer- oder Temp-Ordner. Ohne Erhöhung liegen Programme des Benutzers (HKCU) genau dort.
    param([string] $FilePath, [bool] $Elevated = $true)
    # Liefert $null oder @{ Code; Args } (Text im Modul).
    if (-not $FilePath -or -not [System.IO.Path]::IsPathRooted($FilePath)) { return @{ Code = 'HelperPathNotAbsolute'; Args = @() } }
    $full = [System.IO.Path]::GetFullPath($FilePath)
    if ([System.IO.Path]::GetFileName($full) -ieq 'winget.exe') {
        $apps = (Join-Path $env:ProgramFiles 'WindowsApps').TrimEnd('\') + '\'
        if (-not $full.StartsWith($apps, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
            return @{ Code = 'HelperWingetNotFound'; Args = @($full) }
        }
        return $null
    }
    $blocked = @((Join-Path $env:SystemDrive 'Users'), (Join-Path $env:windir 'Temp'), [System.IO.Path]::GetTempPath()) |
        ForEach-Object { $_.TrimEnd('\') + '\' }
    foreach ($root in $blocked) {
        if ($Elevated -and $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return @{ Code = 'HelperPathInUserFolder'; Args = @($full) } }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return @{ Code = 'HelperFileNotFound'; Args = @($full) } }
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

function Write-HelperLine {
    # Eine Zeile JSON an das Modul (Stapelbetrieb).
    param($Writer, $Result)
    $Writer.WriteLine((ConvertTo-Json -InputObject ([pscustomobject] $Result) -Depth 4 -Compress))
}

function Invoke-ElevatedHelperBatch {
    <#
    .SYNOPSIS
        Stapelbetrieb: mehrere Programme nacheinander mit einer einzigen UAC-Abfrage.
    .DESCRIPTION
        Verbindet sich sofort mit der Pipe des Moduls und meldet zuerst den Wiederherstellungspunkt.
        Vor jedem Schritt wartet der Helfer auf eine Zeile vom Modul: „next“ führt den nächsten Schritt
        aus, alles andere beendet den Stapel (Abbrechen; „Anhalten“ heißt, das Modul antwortet später).
        Nach jedem Schritt meldet er dessen Ergebnis als eigene Zeile. Jeder Schritt durchläuft dieselbe
        Pfadprüfung wie ein Einzelaufruf.
    #>
    param($Plan)
    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream('.', $Plan.PipeName, [System.IO.Pipes.PipeDirection]::InOut)
    $pipe.Connect(30000)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($pipe, $utf8)
    $writer.AutoFlush = $true
    $reader = New-Object System.IO.StreamReader($pipe, $utf8)
    try {
        $start = New-HelperResult $Plan
        $start.Kind = 'Start'
        try {
            if ($Plan.RestorePoint) {
                $rp = Invoke-RestorePoint -Description $Plan.RestorePointDescription -Type ([uint32] $Plan.RestorePointType)
                $start.RestorePoint = $rp.Status
                $start.RestorePointCode = $rp.Code
                $start.RestorePointArgs = @($rp.Args)
            }
        }
        catch { $start.ErrorCode = 'HelperException'; $start.ErrorArgs = @($_.Exception.Message) }
        Write-HelperLine $writer $start

        $index = 0
        foreach ($step in @($Plan.Steps)) {
            if ($reader.ReadLine() -ne 'next') { break }
            $result = New-HelperResult $Plan
            $result.Kind = 'Step'
            $result.Index = $index
            # Eigene Nonce je Schritt nur für den Namen des MSI-Logs
            $stepPlan = [pscustomobject] @{
                FilePath = $step.FilePath; Arguments = $step.Arguments; MsiLog = [bool] $step.MsiLog
                TimeoutSeconds = $step.TimeoutSeconds; Nonce = ('{0}-{1}' -f $Plan.Nonce, $index)
            }
            try {
                $problem = Test-HelperFilePath $step.FilePath -Elevated $true
                if ($problem) { $result.ErrorCode = $problem.Code; $result.ErrorArgs = @($problem.Args) }
                else { Invoke-HelperProcess -Plan $stepPlan -Result $result }
            }
            catch { $result.ErrorCode = 'HelperException'; $result.ErrorArgs = @($_.Exception.Message) }
            Write-HelperLine $writer $result
            $index++
        }
        Write-HelperLine $writer @{ Kind = 'End'; Nonce = $Plan.Nonce }
        $pipe.WaitForPipeDrain()
    }
    finally {
        $pipe.Dispose()
    }
}

function Invoke-ElevatedHelperMain {
    param([string] $PlanBase64)
    $plan = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PlanBase64)) | ConvertFrom-Json
    if ($plan.PSObject.Properties['Steps'] -and $plan.Steps) {
        Invoke-ElevatedHelperBatch -Plan $plan
        return
    }
    $result = New-HelperResult $plan
    try {
        if ($plan.RestorePoint) {
            $rp = Invoke-RestorePoint -Description $plan.RestorePointDescription -Type ([uint32] $plan.RestorePointType)
            $result.RestorePoint = $rp.Status
            $result.RestorePointCode = $rp.Code
            $result.RestorePointArgs = @($rp.Args)
        }
        if ($plan.FilePath) {
            # Fehlt die Angabe (ältere App), gilt die strengere Prüfung für erhöhte Aufrufe.
            $elevated = -not ($plan.PSObject.Properties['Elevate'] -and $plan.Elevate -eq $false)
            $problem = Test-HelperFilePath $plan.FilePath -Elevated $elevated
            if ($problem) { $result.ErrorCode = $problem.Code; $result.ErrorArgs = @($problem.Args) }
            else { Invoke-HelperProcess -Plan $plan -Result $result }
        }
    }
    catch {
        $result.ErrorCode = 'HelperException'
        $result.ErrorArgs = @($_.Exception.Message)
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
