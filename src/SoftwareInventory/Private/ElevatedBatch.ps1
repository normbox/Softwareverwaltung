# Stapelbetrieb des erhöhten Helfers: mehrere Programme mit einer einzigen UAC-Abfrage (Update-Warteschlange).
# Gleicher Schutz wie beim Einzelaufruf (siehe ElevatedRunner.ps1): Hash des Helfers, Pipe nur für
# erhöhte Prozesse, Prozess-ID des Clients, Nonce. Zusätzlich sendet das Modul vor jedem Schritt
# „next“ oder „stop“; der Helfer nimmt nichts anderes an.

function Read-PipeLine {
    # Eine Zeile mit Zeitgrenze; $null bei Zeitüberschreitung oder Ende der Verbindung.
    param([System.IO.StreamReader] $Reader, [int] $TimeoutSeconds)
    $task = $Reader.ReadLineAsync()
    if (-not $task.Wait([timespan]::FromSeconds($TimeoutSeconds))) { return $null }
    $task.Result
}

function Start-ElevatedHelperBatch {
    <#
    .SYNOPSIS
        Führt mehrere Schritte nacheinander in einem erhöhten Helfer aus (eine UAC-Abfrage).
    .DESCRIPTION
        Vor jedem Schritt entscheidet $BeforeStep (Index) mit $true/$false, ob es weitergeht; dort
        wartet die Warteschlange auch, solange sie angehalten ist. Nach jedem Schritt bekommt
        $AfterStep (Index, Ergebnis als Hashtable wie bei Start-ElevatedHelper).
    .OUTPUTS
        @{ Status = Completed|ElevationDenied|Failed; Error; RestorePoint; RestorePointMessage; Done }
    #>
    param(
        [Parameter(Mandatory)] [hashtable[]] $Steps,
        [bool] $RestorePoint,
        [string] $RestorePointDescription,
        [int] $RestorePointType = 0,
        [Parameter(Mandatory)] [scriptblock] $BeforeStep,
        [Parameter(Mandatory)] [scriptblock] $AfterStep,
        [switch] $NoElevation
    )
    $batchNonce = [guid]::NewGuid().ToString('N')
    $batchPipe = "SoftwareInventory-$([guid]::NewGuid().ToString('N'))"
    $batchPlan = @{
        Steps = @($Steps); RestorePoint = $RestorePoint; RestorePointDescription = $RestorePointDescription
        RestorePointType = $RestorePointType; Nonce = $batchNonce; PipeName = $batchPipe
    }
    $batchBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($batchPlan | ConvertTo-Json -Compress -Depth 5)))
    $helper = [System.IO.Path]::GetFullPath($script:ElevatedHelperPath)
    $hash = (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash
    $command = Get-ElevatedHelperBootstrap -HelperPath $helper -Hash $hash -PlanBase64 $batchBase64
    $argumentList = "-NoProfile -NonInteractive -WindowStyle Hidden -Command `"$command`""
    $summary = @{ Status = 'Completed'; Error = $null; RestorePoint = 'NotRequested'; RestorePointMessage = $null; Done = 0 }

    Initialize-PipeInterop
    $server = New-ResultPipe -Name $batchPipe -AllowCurrentUser:$NoElevation -Duplex
    try {
        $connect = $server.WaitForConnectionAsync()
        try {
            $process = Start-ElevatedProcess -FilePath $script:WindowsPowerShell -ArgumentList $argumentList -NoElevation:$NoElevation
        }
        catch {
            if (Test-ElevationCancelled $_) { return @{ Status = 'ElevationDenied'; Error = (New-InventoryMessage ElevationDenied); Done = 0 } }
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperStartFailed $_.Exception.Message); Done = 0 }
        }
        # Bis zur Verbindung: UAC-Abfrage beantworten und Wiederherstellungspunkt (bis 10 Minuten).
        $deadline = [datetime]::UtcNow.AddSeconds(900)
        while (-not $connect.IsCompleted -and -not $process.HasExited -and [datetime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 200 }
        if (-not $connect.IsCompleted) { [void] $connect.Wait(2000) }
        if (-not $connect.IsCompleted -or $connect.IsFaulted) {
            $reason = if ($process.HasExited) { New-InventoryMessage HelperExitedWithoutResult $process.ExitCode } else { New-InventoryMessage HelperNoResponse }
            return @{ Status = 'Failed'; Error = $reason; Done = 0 }
        }
        [uint32] $clientPid = 0
        if (-not [SoftwareInventory.PipeInterop]::GetNamedPipeClientProcessId($server.SafePipeHandle, [ref] $clientPid) -or $clientPid -ne $process.Id) {
            return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperUnexpectedProcess); Done = 0 }
        }
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $reader = [System.IO.StreamReader]::new($server, $utf8)
        $writer = [System.IO.StreamWriter]::new($server, $utf8)
        $writer.AutoFlush = $true

        $line = Read-PipeLine -Reader $reader -TimeoutSeconds 900
        $first = if ($line) { try { $line | ConvertFrom-Json -AsHashtable } catch { $null } }
        if (-not $first -or $first.Nonce -ne $batchNonce) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperResultUnreadable); Done = 0 } }
        if ($first.RestorePoint -and $first.RestorePoint -ne 'NotRequested') {
            $summary.RestorePoint = $first.RestorePoint
            $summary.RestorePointMessage = if ($first.RestorePointCode) { New-InventoryMessage $first.RestorePointCode @($first.RestorePointArgs) }
        }

        for ($stepIndex = 0; $stepIndex -lt $Steps.Count; $stepIndex++) {
            if (-not (& $BeforeStep $stepIndex)) { $writer.WriteLine('stop'); break }
            $writer.WriteLine('next')
            $line = Read-PipeLine -Reader $reader -TimeoutSeconds ([int] $Steps[$stepIndex].TimeoutSeconds + 300)
            $stepRun = if ($line) { try { $line | ConvertFrom-Json -AsHashtable } catch { $null } }
            if (-not $stepRun -or $stepRun.Nonce -ne $batchNonce -or $stepRun.Index -ne $stepIndex) {
                $summary.Status = 'Failed'
                $summary.Error = New-InventoryMessage HelperResultIncomplete
                break
            }
            $stepRun.Status = 'Completed'
            $stepRun.Error = if ($stepRun.ErrorCode) { New-InventoryMessage $stepRun.ErrorCode @($stepRun.ErrorArgs) }
            & $AfterStep $stepIndex $stepRun
            $summary.Done++
        }
        $summary
    }
    catch {
        # Verbindung abgerissen (z. B. Helfer beendet): Rest gilt als fehlgeschlagen.
        $summary.Status = 'Failed'
        $summary.Error = New-InventoryMessage HelperResultIncomplete
        $summary
    }
    finally {
        $server.Dispose()
    }
}
