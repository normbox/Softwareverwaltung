function Remove-RegistryBackup {
    <#
    .SYNOPSIS
        Löscht eine Registry-Sicherung (.reg und .json zusammen). Der Registry-Eintrag selbst bleibt unberührt.
    .DESCRIPTION
        Die Sicherung wird nur über ihre Kennung (Get-RegistryBackup) gefunden, nie über einen Pfad. Auch ältere
        Sicherungen ohne .json lassen sich löschen. Jede Aktion wird protokolliert (Action RemoveBackup);
        -WhatIf liefert den Plan (Result Planned).
    .PARAMETER InputObject
        Kennung (GUID) oder ein Objekt von Get-RegistryBackup.
    .PARAMETER ConfirmedCommandLine
        CommandLine aus dem -WhatIf-Ergebnis (die Kennung). Weicht sie ab, wird nichts gelöscht (Cancelled).
    .PARAMETER LogNotExecutable
        Für Oberflächen, die mit -WhatIf planen: Ist die Aktion nicht ausführbar, wird das trotzdem protokolliert.
    .EXAMPLE
        Get-RegistryBackup | Where-Object IsLegacy | Remove-RegistryBackup -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject,

        [string] $ConfirmedCommandLine,

        [switch] $LogNotExecutable
    )

    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            $plan = New-RemoveBackupPlan -Id (Get-BackupActionInput $item)
            if (-not $plan.Result -and $ConfirmedCommandLine -and $plan.CommandLine -cne $ConfirmedCommandLine) {
                $plan.Result = 'Cancelled'
                $plan.Message = New-InventoryMessage CommandChanged $plan.CommandLine
            }
            $result = New-ActionResult $plan
            if ($plan.Result) {
                $result.CompletedAt = $result.StartedAt
                if (-not $WhatIfPreference -or $LogNotExecutable) { Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result) }
                $result
                continue
            }
            $description = New-InventoryMessage PlanRemoveBackup $plan.Name, $plan.BackupFile
            if (-not $PSCmdlet.ShouldProcess($plan.Name, $description.Text)) {
                $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
                $result.Message = if ($WhatIfPreference) { $description } else { New-InventoryMessage NotConfirmed }
                $result
                continue
            }
            Invoke-RemoveBackupPlan -Plan $plan -Result $result
        }
    }
}

function New-RemoveBackupPlan {
    param([string] $Id)
    $file = Find-RegistryBackupFile -Id $Id
    if (-not $file) {
        $plan = New-BackupActionPlan -Action RemoveBackup -Name $Id -BackupId $Id -NativeKey $null -BackupFile $null -Method File
        $plan.State.Present = $false
        $plan.Result = 'NotInstalled'; $plan.Message = New-InventoryMessage BackupNotFound
        return [pscustomobject] $plan
    }
    $info = Get-RegistryBackupInfo -File $file
    [pscustomobject] (New-BackupActionPlan -Action RemoveBackup -Name $info.Name -BackupId $info.Id -NativeKey $info.NativeKey -BackupFile $file.FullName -Method File)
}

function Invoke-RemoveBackupPlan {
    # Löscht .reg und .json, prüft, dass beide weg sind; protokolliert Start und Ende.
    param($Plan, $Result)
    $Result | Add-Member -NotePropertyName BackupFile -NotePropertyValue $Plan.BackupFile -Force
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $Result)
    try {
        foreach ($path in $Plan.BackupFile, (Get-RegistryBackupSidecarPath $Plan.BackupFile)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop }
        }
    }
    catch {
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage RemoveBackupFailed $_.Exception.Message
    }
    if (-not $Result.Result) {
        $left = @($Plan.BackupFile, (Get-RegistryBackupSidecarPath $Plan.BackupFile) | Where-Object { Test-Path -LiteralPath $_ })
        $Result.PresentAfter = $left.Count -gt 0
        $Result.Result = if ($left.Count -eq 0) { 'Succeeded' } else { 'Failed' }
        $Result.Message = if ($left.Count -eq 0) { New-InventoryMessage RemoveBackupDone } else { New-InventoryMessage RemoveBackupFailed (($left | ForEach-Object { Split-Path -Leaf $_ }) -join ', ') }
    }
    $Result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $Result)
    $Result
}
