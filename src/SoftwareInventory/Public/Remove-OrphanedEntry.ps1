function Remove-OrphanedEntry {
    <#
    .SYNOPSIS
        Entfernt einen verwaisten Uninstall-Eintrag aus der Registry, nach Sicherung als .reg-Datei.
    .DESCRIPTION
        Nur für Einträge mit Flag Orphaned (Programm, Deinstaller und Symbol fehlen). Direkt vor dem Entfernen
        wird der Schlüssel neu gelesen und erneut geprüft: Er muss existieren, direkt unter einem der
        Uninstall-Zweige liegen, darf kein MSI-Eintrag sein und muss weiterhin verwaist sein. Vorerst nur
        Einträge des aktuellen Benutzers (HKCU, ohne Administratorrechte); Einträge für alle Benutzer (HKLM)
        folgen (RemoveEntryMachineNotYet).
        Zuerst sichert reg.exe den Schlüssel nach logs\registry-backup\<ActionId>_<Name>.reg. Fehlt die Datei,
        ist sie leer oder enthält sie den Schlüssel nicht, wird nichts entfernt (RemoveEntryBackupInvalid).
        Entfernt wird nur dieser Schlüssel, nie ein Ordner oder eine Datei. Zurückspielen: Doppelklick auf die
        .reg-Datei oder reg import. Sicherungen werden 365 Tage aufbewahrt. Jede Aktion wird protokolliert;
        -WhatIf liefert den Plan (Result Planned).
    .PARAMETER ConfirmedCommandLine
        CommandLine aus dem -WhatIf-Ergebnis (der Schlüssel). Weicht sie ab, wird nichts entfernt (Cancelled).
    .PARAMETER LogNotExecutable
        Für Oberflächen, die mit -WhatIf planen: Ist die Aktion nicht ausführbar, wird das trotzdem protokolliert.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object { $_.Flags -contains 'Orphaned' } | Remove-OrphanedEntry -WhatIf
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
            $record = Get-ActionRecord $item
            if (-not $record -or -not $record.PSObject.Properties['Name']) {
                Write-Error (Get-LocalizedString 'ErrorNotInventoryRecord')
                continue
            }
            $plan = New-RemoveEntryPlan -Record $record
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
            $description = New-InventoryMessage PlanRemoveEntry $plan.CommandLine, $plan.BackupFile
            if (-not $PSCmdlet.ShouldProcess($plan.Name, $description.Text)) {
                $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
                $result.Message = if ($WhatIfPreference) { $description } else { New-InventoryMessage NotConfirmed }
                $result
                continue
            }
            Invoke-RemoveEntryPlan -Plan $plan -Result $result
        }
    }
}

function New-RemoveEntryPlan {
    # Plan mit erneuter Prüfung des Schlüssels; Result gesetzt, wenn nichts zu entfernen ist.
    param($Record)
    $actionId = [guid]::NewGuid().ToString()
    $keyPath = Get-RecordValue $Record 'RegistryKey'
    $plan = [ordered]@{
        PSTypeName = 'SoftwareInventory.ActionPlan'; ActionId = $actionId; Action = 'RemoveEntry'; Name = $Record.Name
        WingetId = $null; WingetSource = $null; RegistryKey = $keyPath; ProductCode = $null; PackageFullName = $null
        Scope = Get-RecordValue $Record 'Scope'; Method = 'RegistryKey'; FilePath = $null; Arguments = $null; CommandLine = $null
        Elevated = $false; RestorePoint = $false; Result = $null; Message = $null; NextMethod = $null; VendorUrl = $null
        BackupFile = $null; NativeKey = $null
        State = [pscustomobject] @{ Present = $true; Version = $Record.Version }
    }
    $finish = { param($Result, $Message) $plan.Result = $Result; $plan.Message = $Message; [pscustomobject] $plan }

    # Nur ein Schlüssel direkt unter einem der Uninstall-Zweige
    $location = if ($keyPath) {
        Get-DefaultUninstallLocation | Where-Object { [string]::Equals((Split-Path -Parent $keyPath), $_.Path, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    }
    if (-not $location) { return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotUninstallKey $keyPath) }
    if ($location.Scope -ne 'User') { return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryMachineNotYet) }
    $key = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if (-not $key) { $plan.State.Present = $false; return & $finish 'NotInstalled' (New-InventoryMessage RemoveEntryKeyGone) }
    if ($key.GetValue('WindowsInstaller') -eq 1) { return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotOrphaned) }
    $fresh = ConvertFrom-UninstallKey -Key $key -Location $location
    if (-not $fresh -or @(Get-RecordValue $fresh 'Flags') -notcontains 'Orphaned') {
        return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotOrphaned)
    }
    $plan.NativeKey = $key.Name
    $plan.CommandLine = $key.Name
    $plan.BackupFile = Join-Path (Get-RegistryBackupDirectory) (Get-RegistryBackupFileName -ActionId $actionId -Name $Record.Name)
    [pscustomobject] $plan
}

function Invoke-RemoveEntryPlan {
    # Sichern, Sicherung prüfen, Schlüssel entfernen; protokolliert Start und Ende.
    param($Plan, $Result)
    $Result | Add-Member -NotePropertyName BackupFile -NotePropertyValue $Plan.BackupFile -Force
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $Result)
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $Plan.BackupFile) -Force | Out-Null
        $exit = Invoke-RegExport -NativeKey $Plan.NativeKey -File $Plan.BackupFile
        $Result.ExitCode = $exit
        $problem = Test-RegistryBackup -File $Plan.BackupFile -NativeKey $Plan.NativeKey
        if ($exit -ne 0 -or $problem) {
            # Unbrauchbare Sicherung nicht liegen lassen; der Schlüssel bleibt unberührt.
            Remove-Item -LiteralPath $Plan.BackupFile -Force -ErrorAction SilentlyContinue
            $Result.Result = 'Failed'
            $Result.Message = New-InventoryMessage RemoveEntryBackupInvalid $(if ($problem) { $problem } else { "Exit $exit" })
            $Result.BackupFile = $null
        }
        else {
            Remove-Item -LiteralPath $Plan.RegistryKey -Recurse -Force -ErrorAction Stop
            $gone = -not (Test-Path -LiteralPath $Plan.RegistryKey)
            $Result.PresentAfter = -not $gone
            $Result.Result = if ($gone) { 'Succeeded' } else { 'Failed' }
            $Result.Message = if ($gone) { New-InventoryMessage RemoveEntryDone $Plan.BackupFile } else { New-InventoryMessage RemoveEntryDeleteFailed '' }
        }
    }
    catch {
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage RemoveEntryDeleteFailed $_.Exception.Message
    }
    $Result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $Result)
    $Result
}
