function Clear-ExpiredRegistryBackup {
    <#
    .SYNOPSIS
        Löscht abgelaufene HKLM-Sicherungen (älter als 365 Tage) und Reste im Admin-Ordner über den erhöhten Helfer.
    .DESCRIPTION
        Braucht Administratorrechte (UAC-Abfrage, Operation CleanupRegistryBackups); deshalb nie automatisch beim Start.
        Der Helfer entscheidet selbst, was abgelaufen ist (feste Frist, Änderungszeit der .reg), und löscht nur Dateien
        mit eigenem Namensschema. -WhatIf nennt die Anzahl abgelaufener Sicherungen (Result Planned); gibt es keine,
        passiert nichts (Result NotInstalled, ClearExpiredBackupsNothing). Jede Ausführung wird protokolliert
        (Action ClearExpiredBackups). Sicherungen des Benutzers räumt die Selbstbereinigung beim Start auf.
    .PARAMETER LogNotExecutable
        Für Oberflächen, die mit -WhatIf planen: Ist die Aktion nicht ausführbar, wird das trotzdem protokolliert.
    .EXAMPLE
        Clear-ExpiredRegistryBackup -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [string] $ConfirmedCommandLine,

        [switch] $LogNotExecutable
    )

    $status = Get-RegistryBackupStatus
    $plan = New-BackupActionPlan -Action ClearExpiredBackups -Name (Get-LocalizedString 'BackupsMachineName') -BackupId $null -NativeKey $null -BackupFile $status.MachineFolder -Method File -Scope Machine
    $plan.CommandLine = $status.MachineFolder
    if ($status.MachineFolderState -eq 'Unreadable') {
        $plan.Result = 'Unsupported'; $plan.Message = New-InventoryMessage BackupFolderUnreadable $status.MachineFolder
    }
    elseif ($status.ExpiredMachineCount -eq 0) {
        $plan.State.Present = $false
        $plan.Result = 'NotInstalled'; $plan.Message = New-InventoryMessage ClearExpiredBackupsNothing
    }
    $plan = [pscustomobject] $plan
    if (-not $plan.Result -and $ConfirmedCommandLine -and $plan.CommandLine -cne $ConfirmedCommandLine) {
        $plan.Result = 'Cancelled'
        $plan.Message = New-InventoryMessage CommandChanged $plan.CommandLine
    }
    $result = New-ActionResult $plan
    if ($plan.Result) {
        $result.CompletedAt = $result.StartedAt
        if (-not $WhatIfPreference -or $LogNotExecutable) { Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result) }
        return $result
    }
    $description = New-InventoryMessage PlanClearExpiredBackups $status.ExpiredMachineCount, $status.RetentionDays
    if (-not $PSCmdlet.ShouldProcess($plan.Name, $description.Text)) {
        $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
        $result.Message = if ($WhatIfPreference) { $description } else { New-InventoryMessage NotConfirmed }
        return $result
    }

    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $result)
    try {
        $run = Invoke-BackupHelper -HelperPlan @{ Operation = 'CleanupRegistryBackups' }
        $left = (Get-RegistryBackupStatus).ExpiredMachineCount
        $result.PresentAfter = $left -gt 0
        $deleted = if ($null -ne $run.Deleted) { [int] $run.Deleted } else { 0 }
        Complete-BackupHelperResult -Result $result -Run $run -Verified ($left -eq 0) -SuccessMessage (New-InventoryMessage ClearExpiredBackupsDone $deleted)
    }
    catch {
        $result.Result = 'Failed'
        $result.Message = New-InventoryMessage RemoveBackupFailed $_.Exception.Message
    }
    $result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result)
    $result
}
