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

function Initialize-PipeInterop {
    if ('SoftwareInventory.PipeInterop' -as [type]) { return }
    Add-Type -Namespace SoftwareInventory -Name PipeInterop -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetNamedPipeClientProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe, out uint clientProcessId);
'@
}

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
    # Kapselt Start-Process, damit Tests es ersetzen können. -Verb RunAs löst die UAC-Abfrage aus.
    param([string] $FilePath, [string] $ArgumentList, [switch] $NoElevation)
    $parameters = @{ FilePath = $FilePath; ArgumentList = $ArgumentList; PassThru = $true; WindowStyle = 'Hidden' }
    if (-not $NoElevation) { $parameters.Verb = 'RunAs' }
    Start-Process @parameters
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
        Hashtable: Status (Completed|ElevationDenied|Failed) und die Felder des Helfers
        (RestorePoint, ExitCode, TimedOut, Output, InstallerLog, Error).
    .PARAMETER NoElevation
        Startet den Helfer ohne UAC im aktuellen Benutzer und lässt diesen an die Pipe. So laufen
        Aktionen ohne Adminrechte (HKCU, unbekannter Bereich) über denselben Weg.
    #>
    param(
        [Parameter(Mandatory)] [hashtable] $HelperPlan,
        [int] $TimeoutSeconds = 3600,
        [switch] $NoElevation
    )

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

    Initialize-PipeInterop
    $server = New-ResultPipe -Name $pipeName -AllowCurrentUser:$NoElevation
    try {
        $connect = $server.WaitForConnectionAsync()
        try {
            $process = Start-ElevatedProcess -FilePath $script:WindowsPowerShell -ArgumentList $argumentList -NoElevation:$NoElevation
        }
        catch {
            if (Test-ElevationCancelled $_) { return @{ Status = 'ElevationDenied'; Error = (New-InventoryMessage ElevationDenied) } }
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperStartFailed $_.Exception.Message) }
        }

        # Restore-Point und Aktion brauchen Zeit; zusätzlich 10 Minuten Puffer.
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

        $reader = [System.IO.StreamReader]::new($server, [System.Text.Encoding]::UTF8)
        $read = $reader.ReadToEndAsync()
        if (-not $read.Wait([timespan]::FromSeconds(60))) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultIncomplete) } }
        try {
            $result = $read.Result | ConvertFrom-Json -AsHashtable
        }
        catch {
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultUnreadable) }
        }
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
