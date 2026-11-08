# Start des erhöhten Helfers und Rückweg des Ergebnisses über eine Named Pipe.
#
# Start-ElevatedHelper ist die EINZIGE Stelle, die einen erhöhten Prozess startet. Heute ist das
# Windows PowerShell 5.1 (powershell.exe, auf jedem Windows 10/11 vorhanden). In Etappe 3b ersetzt
# die App nur diese Funktion durch ihre eigene EXE mit Helfer-Argument; der Helfer bleibt gleich.
#
# Schutz:
# - Der Plan steht als Base64-JSON im Argument, nicht in einer Datei, die man austauschen könnte.
# - Der erhöhte Prozess liest das Helferskript einmal in den Speicher, prüft dessen SHA256 und
#   führt genau diesen Inhalt aus.
# - Die Pipe hat einen zufälligen Namen; verbinden dürfen nur erhöhte Prozesse (Administratoren,
#   SYSTEM). Zusätzlich muss die Prozess-ID des Clients die des gestarteten Helfers sein und die
#   Zufallszahl (Nonce) aus dem Plan zurückkommen. Es wird nur eine begrenzte Zeit gewartet.

$script:ElevatedHelperPath = Join-Path $PSScriptRoot '..\Elevated\ElevatedHelper.ps1'
$script:WindowsPowerShell = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'

# Prozess-ID der Pipe-Gegenstelle: [SoftwareInventory.PipeInterop] aus lib\SoftwareInventory.Native.dll.

function New-ResultPipe {
    <#
    .SYNOPSIS
        Erzeugt den Server einer Named Pipe, mit der sich nur erhöhte Prozesse verbinden dürfen.
    .PARAMETER AllowCurrentUser
        Nur für Tests: erlaubt auch dem aktuellen Benutzer ohne Adminrechte die Verbindung.
    .PARAMETER Duplex
        In beide Richtungen (Stapelbetrieb: das Modul sendet „next“/„stop“).
    #>
    param([Parameter(Mandatory)] [string] $Name, [switch] $AllowCurrentUser, [switch] $Duplex)

    $security = [System.IO.Pipes.PipeSecurity]::new()
    $rights = [System.IO.Pipes.PipeAccessRights]::ReadWrite
    foreach ($sid in @(
            [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
            [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
        )) {
        $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new($sid, $rights, 'Allow'))
    }
    if ($AllowCurrentUser) {
        $security.AddAccessRule([System.IO.Pipes.PipeAccessRule]::new([System.Security.Principal.WindowsIdentity]::GetCurrent().User, $rights, 'Allow'))
    }
    $direction = if ($Duplex) { [System.IO.Pipes.PipeDirection]::InOut } else { [System.IO.Pipes.PipeDirection]::In }
    [System.IO.Pipes.NamedPipeServerStreamAcl]::Create($Name, $direction, 1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte, [System.IO.Pipes.PipeOptions]::Asynchronous, 0, 0, $security)
}

function Get-ElevatedHelperBootstrap {
    # Kurzer Startbefehl für -Command: Skript lesen, Hash prüfen, Inhalt ausführen. Nur einfache Anführungszeichen.
    param([string] $HelperPath, [string] $Hash, [string] $PlanBase64)
    $path = $HelperPath.Replace("'", "''")
    # Telemetrie aus, bevor irgendetwas läuft: ein mit UAC gestarteter Prozess erbt die Umgebung der App nicht.
    "`$env:POWERSHELL_TELEMETRY_OPTOUT='1';" +
    "`$b=[IO.File]::ReadAllBytes('$path');" +
    "`$h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(`$b)).Replace('-','');" +
    "if(`$h -ne '$Hash'){exit 3};" +
    "`$t=[Text.Encoding]::UTF8.GetString(`$b).TrimStart([char]0xFEFF);" +
    "& ([scriptblock]::Create(`$t)) -PlanBase64 '$PlanBase64'"
}

function Start-ElevatedProcess {
    # Kapselt den Start, damit Tests ihn ersetzen können. Mit Erhöhung über ShellExecuteEx und dem Fenster
    # der App als Besitzer, damit die UAC-Abfrage vorne erscheint; Start-Process kann das nicht.
    param([string] $FilePath, [string] $ArgumentList, [switch] $NoElevation)
    if ($NoElevation) { return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru -WindowStyle Hidden }
    $owner = (Get-Process -Id $PID).MainWindowHandle
    [SoftwareInventory.ElevationInterop]::Start($FilePath, $ArgumentList, $owner)
}

function Set-ActionPhase {
    # Für die Anzeige in der App: WaitingForElevation (UAC-Abfrage offen) oder Running.
    param([System.Collections.IDictionary] $Control, [string] $Phase)
    if ($Control) { $Control['Phase'] = $Phase }
}

function Test-ActionCancelRequested {
    param([System.Collections.IDictionary] $Control)
    [bool] ($Control -and $Control['State'] -eq 'Cancelled')
}

function Receive-HelperLine {
    <#
    .SYNOPSIS
        Wartet auf die nächste Ergebniszeile des Helfers und reicht währenddessen ein Abbrechen weiter.
    .DESCRIPTION
        Sobald die App abbricht (Control.State = Cancelled), geht einmal „cancel“ an den Helfer. Seine
        Antwort (CancelReply) landet in Control.CancelResult: Stopped, Continuing oder Orphaned.
    .OUTPUTS
        Hashtable der Zeile; $null bei Zeitüberschreitung, Verbindungsende oder unlesbarer Zeile.
    #>
    param(
        [System.IO.StreamReader] $Reader,
        [System.IO.StreamWriter] $Writer,
        [System.Collections.IDictionary] $Control,
        [int] $TimeoutSeconds
    )
    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    $sent = $false
    try {
        $task = $Reader.ReadLineAsync()
        while ($true) {
            if ($task.Wait(250)) {
                $line = $task.Result
                if ($null -eq $line) { return $null }
                $data = try { $line | ConvertFrom-Json -AsHashtable } catch { $null }
                if ($data -and $data.Kind -eq 'CancelReply') {
                    if ($Control) { $Control['CancelResult'] = $data.Outcome }
                    $task = $Reader.ReadLineAsync()
                    continue
                }
                return $data
            }
            if ([datetime]::UtcNow -ge $deadline) { return $null }
            if (-not $sent -and (Test-ActionCancelRequested $Control)) {
                $sent = $true
                $Writer.WriteLine('cancel')
            }
        }
    }
    catch {
        # Verbindung abgerissen (Helfer beendet)
        $null
    }
}

function Test-ElevationCancelled {
    # UAC-Abfrage abgelehnt: Win32-Fehler 1223 (ERROR_CANCELLED).
    param($ErrorRecord)
    $e = $ErrorRecord.Exception
    while ($e) {
        if ($e -is [System.ComponentModel.Win32Exception] -and $e.NativeErrorCode -eq 1223) { return $true }
        $e = $e.InnerException
    }
    $false
}

function Start-ElevatedHelper {
    <#
    .SYNOPSIS
        Führt einen Plan im erhöhten Helfer aus und liefert dessen Ergebnis.
    .OUTPUTS
        Hashtable: Status (Completed|ElevationDenied|Cancelled|Failed) und die Felder des Helfers
        (RestorePoint, ExitCode, TimedOut, Cancelled, Output, InstallerLog, Error).
    .PARAMETER NoElevation
        Startet den Helfer ohne UAC im aktuellen Benutzer und lässt diesen an die Pipe. So laufen
        Aktionen ohne Adminrechte (HKCU, unbekannter Bereich) über denselben Weg.
    .PARAMETER Control
        Synchronisierte Hashtabelle der App: State = Cancelled bricht ab; Phase und CancelResult schreibt das Modul.
    #>
    param(
        [Parameter(Mandatory)] [hashtable] $HelperPlan,
        [int] $TimeoutSeconds = 3600,
        [switch] $NoElevation,
        [System.Collections.IDictionary] $Control
    )

    if (Test-ActionCancelRequested $Control) { return @{ Status = 'Cancelled'; Error = (New-InventoryMessage ActionCancelledBeforeStart) } }

    $nonce = [guid]::NewGuid().ToString('N')
    $pipeName = "SoftwareInventory-$([guid]::NewGuid().ToString('N'))"
    $data = @{} + $HelperPlan
    $data.Nonce = $nonce
    $data.PipeName = $pipeName
    $data.TimeoutSeconds = $TimeoutSeconds
    $planBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($data | ConvertTo-Json -Compress -Depth 4)))

    $helper = [System.IO.Path]::GetFullPath($script:ElevatedHelperPath)
    $hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
    $command = Get-ElevatedHelperBootstrap -HelperPath $helper -Hash $hash -PlanBase64 $planBase64
    $argumentList = "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$command`""

    $server = New-ResultPipe -Name $pipeName -AllowCurrentUser:$NoElevation -Duplex
    try {
        $connect = $server.WaitForConnectionAsync()
        try {
            # Der Start kehrt erst zurück, wenn die UAC-Abfrage beantwortet ist; sie lässt sich von außen nicht schließen.
            Set-ActionPhase $Control $(if ($NoElevation) { 'Running' } else { 'WaitingForElevation' })
            $process = Start-ElevatedProcess -FilePath $script:WindowsPowerShell -ArgumentList $argumentList -NoElevation:$NoElevation
        }
        catch {
            if (Test-ElevationCancelled $_) { return @{ Status = 'ElevationDenied'; Error = (New-InventoryMessage ElevationDenied) } }
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperStartFailed $_.Exception.Message) }
        }
        Set-ActionPhase $Control 'Running'

        # Bis zur Verbindung: Start des Helfers; zusätzlich 10 Minuten Puffer.
        $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds + 600)
        while (-not $connect.IsCompleted -and -not $process.HasExited -and [datetime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 200
        }
        if (-not $connect.IsCompleted) {
            # Ein kurz vor dem Ende verbundener Client soll nicht verloren gehen.
            [void] $connect.Wait(2000)
        }
        if (-not $connect.IsCompleted -or $connect.IsFaulted) {
            $reason = if ($process.HasExited) { New-InventoryMessage HelperExitedWithoutResult $process.ExitCode } else { New-InventoryMessage HelperNoResponse }
            return @{ Status = 'Failed'; Error = $reason }
        }

        [uint32] $clientPid = 0
        if (-not [SoftwareInventory.PipeInterop]::GetNamedPipeClientProcessId($server.SafePipeHandle, [ref] $clientPid) -or $clientPid -ne $process.Id) {
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperUnexpectedProcess) }
        }

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $reader = [System.IO.StreamReader]::new($server, $utf8)
        $writer = [System.IO.StreamWriter]::new($server, $utf8)
        $writer.AutoFlush = $true

        # Handschlag: Erst nach „go“ startet der Helfer etwas.
        $hello = Receive-HelperLine -Reader $reader -Writer $writer -TimeoutSeconds 60
        if (-not $hello) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultUnreadable) } }
        if ($hello.Nonce -ne $nonce) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperNonceMismatch) } }
        try {
            if (Test-ActionCancelRequested $Control) {
                $writer.WriteLine('stop')
                return @{ Status = 'Cancelled'; Error = (New-InventoryMessage ActionCancelledBeforeStart) }
            }
            $writer.WriteLine('go')
        }
        catch {
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultIncomplete) }
        }

        # Restore-Point und Aktion brauchen Zeit; zusätzlich 10 Minuten Puffer.
        $result = Receive-HelperLine -Reader $reader -Writer $writer -Control $Control -TimeoutSeconds ($TimeoutSeconds + 600)
        if (-not $result) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultIncomplete) } }
        if ($result.Nonce -ne $nonce) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperNonceMismatch) } }
        $result.Status = 'Completed'
        # Der Helfer liefert nur Codes; den Text bildet das Modul in der Sprache der Oberfläche.
        $result.RestorePointMessage = if ($result.RestorePointCode) { New-InventoryMessage $result.RestorePointCode @($result.RestorePointArgs) }
        $result.Error = if ($result.ErrorCode) { New-InventoryMessage $result.ErrorCode @($result.ErrorArgs) }
        $result
    }
    finally {
        $server.Dispose()
    }
}
