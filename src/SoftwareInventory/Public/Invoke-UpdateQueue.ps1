function Invoke-UpdateQueue {
    <#
    .SYNOPSIS
        Führt eine bestätigte Update-Warteschlange aus (Einträge aus Get-UpdateQueuePlan).
    .DESCRIPTION
        Ablauf:
          1. Jeder Eintrag wird mit seinem bestätigten Befehl neu geplant. Weicht der Befehl ab, wird nur
             dieser Eintrag übersprungen (Cancelled, CommandChanged) – wie bei -ConfirmedCommandLine.
          2. Erhöhte Einträge laufen zuerst in einem einzigen erhöhten Helfer: eine UAC-Abfrage, davor
             (falls eingestellt) ein einziger Wiederherstellungspunkt für die ganze Warteschlange.
          3. Danach die Einträge ohne Administratorrechte, nacheinander. Programme im Benutzerbereich
             laufen nie erhöht.
        Fehler halten die Warteschlange nicht an; für den Eintrag nennt NextMethod die nächste Methode
        (kein automatisches Ausweichen). Jede Aktion wird einzeln protokolliert.

        -Control ist eine synchronisierte Hashtabelle, die die App während des Laufs liest und setzt:
          State  – Running, Paused oder Cancelled (zwischen zwei Einträgen geprüft; die laufende Aktion
                   wird immer fertig)
          Status – je Index: Waiting, Running oder das Ergebnis (Succeeded, Failed, Cancelled, …)
        Nach Abbrechen werden die übrigen Einträge als Cancelled (QueueCancelled) protokolliert.
    .EXAMPLE
        $plan = $ratings | Get-UpdateQueuePlan
        $control = [hashtable]::Synchronized(@{ State = 'Running' })
        Invoke-UpdateQueue -Entry ($plan | Where-Object Executable) -Control $control
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Entry,
        [System.Collections.IDictionary] $Control,
        [switch] $CreateRestorePoint,
        [ValidateRange(1, 1440)] [int] $TimeoutMinutes = 60
    )

    $restorePoint = if ($PSBoundParameters.ContainsKey('CreateRestorePoint')) { $CreateRestorePoint.IsPresent } else { [bool] (Read-InventorySetting).Actions.RestorePoint }
    if (-not $Control) { $Control = [hashtable]::Synchronized(@{}) }
    if (-not $Control.Contains('State')) { $Control['State'] = 'Running' }
    $queueStatus = [hashtable]::Synchronized(@{})
    $Control['Status'] = $queueStatus
    $queueResults = @{}
    $queueItems = [System.Collections.Generic.List[object]]::new()

    # 1. Mit dem bestätigten Befehl neu planen
    foreach ($e in @($Entry | Where-Object { $_ -and $_.Executable })) {
        $queueStatus[[int] $e.Index] = 'Waiting'
        $p = Resolve-SoftwareAction -Action Update -InputObject $e.InputObject -RestorePoint $false -ConfirmedCommandLine $e.CommandLine
        if (-not $p) { continue }
        if ($p.Result) {
            $queueResults[[int] $e.Index] = $p.Result
            $queueStatus[[int] $e.Index] = $p.Result.Result
            continue
        }
        $queueItems.Add(@{ Index = [int] $e.Index; Prepared = $p })
    }
    $elevatedItems = @($queueItems | Where-Object { $_.Prepared.Plan.Elevated })
    $normalItems = @($queueItems | Where-Object { -not $_.Prepared.Plan.Elevated })
    $total = $queueItems.Count
    $script:QueueDone = 0
    $restoreInfo = $null

    # Zwischen zwei Einträgen: angehalten warten, abgebrochen beenden.
    $continueQueue = {
        while ($Control['State'] -eq 'Paused') { Start-Sleep -Milliseconds 250 }
        $Control['State'] -ne 'Cancelled'
    }

    # 2. Erhöhte Einträge: ein Helfer, eine UAC-Abfrage, davor ein Wiederherstellungspunkt
    if ($elevatedItems) {
        $startedResults = @{}
        $steps = @($elevatedItems | ForEach-Object {
                @{ FilePath = $_.Prepared.Plan.FilePath; Arguments = $_.Prepared.Plan.Arguments; MsiLog = [bool] $_.Prepared.Plan.MsiLog; TimeoutSeconds = $TimeoutMinutes * 60 }
            })
        $before = {
            param($stepIndex)
            if (-not (& $continueQueue)) { return $false }
            $item = $elevatedItems[$stepIndex]
            $started = New-ActionResult $item.Prepared.Plan
            Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $started)
            $startedResults[$stepIndex] = $started
            $queueStatus[$item.Index] = 'Running'
            Write-CheckProgress -Id 6 -Activity ProgressUpdateQueue -Index ($script:QueueDone + 1) -Total $total -Name $item.Prepared.Plan.Name
            $true
        }
        $after = {
            param($stepIndex, $run)
            $item = $elevatedItems[$stepIndex]
            $read = Read-HelperRun -Result $startedResults[$stepIndex] -Run $run -TimeoutMinutes $TimeoutMinutes
            $final = Complete-ActionResult -Plan $item.Prepared.Plan -Record $item.Prepared.Record -Result $startedResults[$stepIndex] -Outcome $read.Outcome -Failure $read.Failure
            $queueResults[$item.Index] = $final
            $queueStatus[$item.Index] = $final.Result
            $script:QueueDone++
        }
        $batch = Start-ElevatedHelperBatch -Steps $steps -BeforeStep $before -AfterStep $after -RestorePoint $restorePoint `
            -RestorePointDescription (New-InventoryMessage RestorePointNameQueue $total).Text -RestorePointType $script:RestorePointType['Update']
        if ($restorePoint) { $restoreInfo = @{ RestorePoint = $batch.RestorePoint; RestorePointMessage = $batch.RestorePointMessage } }
        if ($batch.Status -ne 'Completed') {
            # UAC abgelehnt oder Helfer gescheitert: betrifft nur die erhöhten Einträge ohne Ergebnis.
            $code = if ($batch.Status -eq 'ElevationDenied') { 'ElevationDenied' } else { 'Failed' }
            foreach ($item in $elevatedItems | Where-Object { -not $queueResults.ContainsKey($_.Index) }) {
                $r = New-ActionResult $item.Prepared.Plan
                $r.Result = $code
                $r.Message = $batch.Error
                $r.CompletedAt = [datetime]::UtcNow
                Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $r)
                $queueResults[$item.Index] = $r
                $queueStatus[$item.Index] = $code
            }
        }
    }
    elseif ($restorePoint -and $normalItems) {
        # Nur Einträge ohne Adminrechte: Wiederherstellungspunkt mit eigener kurzer UAC-Abfrage.
        $rp = Start-ElevatedHelper -TimeoutSeconds 600 -HelperPlan @{
            FilePath = $null; RestorePoint = $true
            RestorePointDescription = (New-InventoryMessage RestorePointNameQueue $total).Text; RestorePointType = $script:RestorePointType['Update']
        }
        $restoreInfo = if ($rp['Status'] -eq 'Completed') { @{ RestorePoint = $rp['RestorePoint']; RestorePointMessage = $rp['RestorePointMessage'] } }
        else { @{ RestorePoint = 'Failed'; RestorePointMessage = (New-InventoryMessage RestorePointContinueWithout (, $rp['Error'])) } }
    }

    # 3. Einträge ohne Adminrechte, nacheinander
    foreach ($item in $normalItems) {
        if (-not (& $continueQueue)) { break }
        $queueStatus[$item.Index] = 'Running'
        Write-CheckProgress -Id 6 -Activity ProgressUpdateQueue -Index ($script:QueueDone + 1) -Total $total -Name $item.Prepared.Plan.Name
        $final = Invoke-ActionPlan -Plan $item.Prepared.Plan -Record $item.Prepared.Record -TimeoutMinutes $TimeoutMinutes
        $queueResults[$item.Index] = $final
        $queueStatus[$item.Index] = $final.Result
        $script:QueueDone++
    }

    # Abgebrochen: übrige Einträge protokollieren, nichts davon wurde gestartet.
    foreach ($item in $queueItems | Where-Object { -not $queueResults.ContainsKey($_.Index) }) {
        $r = New-ActionResult $item.Prepared.Plan
        $r.Result = 'Cancelled'
        $r.Message = New-InventoryMessage QueueCancelled
        $r.CompletedAt = [datetime]::UtcNow
        Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $r)
        $queueResults[$item.Index] = $r
        $queueStatus[$item.Index] = 'Cancelled'
    }
    Write-CheckProgress -Id 6 -Activity ProgressUpdateQueue -Completed

    # Der eine Wiederherstellungspunkt gehört zum ersten ausgeführten Eintrag.
    $ordered = @($queueResults.Keys | Sort-Object | ForEach-Object { $queueResults[$_] })
    if ($restoreInfo) {
        $first = $ordered | Where-Object { $_.Result -ne 'Cancelled' -or $_.StartedAt -ne $_.CompletedAt } | Select-Object -First 1
        if ($first) { $first.RestorePoint = $restoreInfo.RestorePoint; $first.RestorePointMessage = $restoreInfo.RestorePointMessage }
    }
    $ordered
}
