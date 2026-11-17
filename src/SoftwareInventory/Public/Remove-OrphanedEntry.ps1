function Remove-OrphanedEntry {
    <#
    .SYNOPSIS
        Entfernt einen verwaisten Uninstall-Eintrag aus der Registry, nach Sicherung als .reg-Datei.
    .DESCRIPTION
        Nur für Einträge mit Flag Orphaned (Programm, Deinstaller und Symbol fehlen). Direkt vor dem Entfernen
        wird der Schlüssel neu gelesen und erneut geprüft: Er muss existieren, direkt unter einem der
        Uninstall-Zweige liegen, darf kein MSI-Eintrag sein und muss weiterhin verwaist sein.
        Einträge des aktuellen Benutzers (HKCU, ohne Administratorrechte): Zuerst sichert reg.exe den Schlüssel nach
        logs\registry-backup\<ActionId>_<Name>.reg und das Modul schreibt daneben <ActionId>_<Name>.json (Name,
        Schlüssel, Gründe als Codes). Fehlt die .reg-Datei, ist sie leer oder besteht sie die strenge Prüfung
        (Test-RegistryBackupContent) nicht, wird nichts entfernt (RemoveEntryBackupInvalid); ebenso, wenn die .json
        nicht geschrieben werden kann.
        Einträge für alle Benutzer (HKLM): Der erhöhte Helfer (UAC-Abfrage, Operation RemoveRegistryEntry) prüft alles
        erneut, sichert nach Program Files\Softwareverwaltung\RegistryBackup\<ActionId>.reg (mit .json) und entfernt
        erst dann den Schlüssel. Erfolg nur, wenn der Helfer das meldet, die Sicherung am geplanten Ort liegt und der
        Schlüssel in der 64-Bit-Ansicht weg ist. Ein Wiederherstellungspunkt wird nie angelegt (die Sicherung ersetzt ihn).
        Entfernt wird nur dieser Schlüssel samt Unterschlüsseln, nie ein Ordner oder eine Datei. Zurückspielen:
        Restore-RegistryBackup; Sicherungen werden 365 Tage aufbewahrt (beides vorerst nur HKCU, HKLM folgt). Jede Aktion wird protokolliert;
        -WhatIf liefert den Plan (Result Planned).
        Gründe (Reasons am Eingabeobjekt) übernimmt das Modul nur, wenn der Code bekannt ist.
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
            $plan = New-RemoveEntryPlan -Record $record -Reasons (Get-RecordValue $item 'Reasons')
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
            $description = if ($plan.Elevated) { New-InventoryMessage PlanRemoveEntryMachine $plan.CommandLine, $plan.BackupFile } else { New-InventoryMessage PlanRemoveEntry $plan.CommandLine, $plan.BackupFile }
            if (-not $PSCmdlet.ShouldProcess($plan.Name, $description.Text)) {
                $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
                $result.Message = if ($WhatIfPreference) { $description } else { New-InventoryMessage NotConfirmed }
                $result
                continue
            }
            if ($plan.Elevated) { Invoke-RemoveMachineEntryPlan -Plan $plan -Result $result }
            else { Invoke-RemoveEntryPlan -Plan $plan -Result $result }
        }
    }
}

function New-RemoveEntryPlan {
    # Plan mit erneuter Prüfung des Schlüssels; Result gesetzt, wenn nichts zu entfernen ist.
    param($Record, $Reasons)
    $actionId = [guid]::NewGuid().ToString()
    $keyPath = Get-RecordValue $Record 'RegistryKey'
    $plan = [ordered]@{
        PSTypeName = 'SoftwareInventory.ActionPlan'; ActionId = $actionId; Action = 'RemoveEntry'; Name = $Record.Name
        WingetId = $null; WingetSource = $null; RegistryKey = $keyPath; ProductCode = $null; PackageFullName = $null
        Scope = Get-RecordValue $Record 'Scope'; Method = 'RegistryKey'; FilePath = $null; Arguments = $null; CommandLine = $null
        Elevated = $false; RestorePoint = $false; Result = $null; Message = $null; NextMethod = $null; VendorUrl = $null
        BackupFile = $null; NativeKey = $null; Reasons = @(); HelperInWritableFolder = $false
        State = [pscustomobject] @{ Present = $true; Version = $Record.Version }
    }
    $finish = { param($Result, $Message) $plan.Result = $Result; $plan.Message = $Message; [pscustomobject] $plan }

    # Nur ein Schlüssel direkt unter einem der Uninstall-Zweige
    $location = if ($keyPath) {
        Get-DefaultUninstallLocation | Where-Object { [string]::Equals((Split-Path -Parent $keyPath), $_.Path, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    }
    if (-not $location) { return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotUninstallKey $keyPath) }
    # [ ] oder Steuerzeichen im Namen: nie sicher zu sichern oder zu lesen (Handarbeit); schon die Planung nennt den Grund.
    if ($keyPath.Substring($keyPath.LastIndexOf('\') + 1) -cmatch $script:UnsafeKeyNamePattern) { return & $finish 'Unsupported' (New-InventoryMessage BackupKeyNameUnsafe) }
    $key = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
    if (-not $key) { $plan.State.Present = $false; return & $finish 'NotInstalled' (New-InventoryMessage RemoveEntryKeyGone) }
    if ($key.GetValue('WindowsInstaller') -eq 1) { return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotOrphaned) }
    $fresh = ConvertFrom-UninstallKey -Key $key -Location $location
    if (-not $fresh -or @(Get-RecordValue $fresh 'Flags') -notcontains 'Orphaned') {
        return & $finish 'Unsupported' (New-InventoryMessage RemoveEntryNotOrphaned)
    }
    $plan.NativeKey = $key.Name
    $plan.CommandLine = $key.Name
    # Nur bekannte Gründe; die erneute Prüfung oben hat Orphaned bestätigt, der Grund steht also immer dabei.
    $known = @(ConvertTo-KnownBackupReason $Reasons)
    if (-not ($known | Where-Object { $_.Code -ceq 'OrphanedEntry' })) { $known = @([ordered]@{ Code = 'OrphanedEntry'; Args = @() }) + $known }
    $plan.Reasons = $known
    if ($location.Scope -eq 'Machine') {
        # HKLM: nur über den erhöhten Helfer; er legt die Sicherung im Admin-Ordner unter genau diesem Namen an.
        $plan.Elevated = $true
        $plan.BackupFile = Join-Path (Get-RegistryBackupMachineDirectory) "$actionId.reg"
        $plan.HelperInWritableFolder = [bool] (Test-HelperInWritableFolder)
    }
    else {
        $plan.BackupFile = Join-Path (Get-RegistryBackupDirectory) (Get-RegistryBackupFileName -ActionId $actionId -Name $Record.Name)
    }
    [pscustomobject] $plan
}

function Invoke-RemoveMachineEntryPlan {
    <#
    .SYNOPSIS
        HKLM-Eintrag über den erhöhten Helfer sichern und entfernen; protokolliert Start und Ende.
    .DESCRIPTION
        Der Helfer bekommt nur Schlüssel, ActionId und die bekannten Gründe; alles andere prüft er selbst. Als Erfolg
        zählt nur: Der Helfer meldet Removed ohne Fehler, die Sicherung liegt genau am geplanten Ort, und der Schlüssel
        ist in der 64-Bit-Ansicht weg (Test-MachineRegistryKeyPresent, wie der Helfer).
    #>
    param($Plan, $Result)
    $Result | Add-Member -NotePropertyName BackupFile -NotePropertyValue $Plan.BackupFile -Force
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $Result)
    $reasons = @(foreach ($reason in @($Plan.Reasons)) { @{ Code = [string] $reason.Code; Args = @($reason.Args | ForEach-Object { [string] $_ }) } })
    try {
        $run = Start-ElevatedHelper -TimeoutSeconds 300 -HelperPlan @{
            Operation = 'RemoveRegistryEntry'; RegistryKey = $Plan.RegistryKey; ActionId = $Plan.ActionId; Reasons = $reasons; RestorePoint = $false
        }
        # Über den Indexer lesen: Fehler-Ergebnisse (abgelehnt, zu alt) haben nicht alle Felder, und StrictMode wirft sonst.
        $field = { param($Name) if ($run -is [System.Collections.IDictionary] -and $run.Contains($Name)) { $run[$Name] } }
        $status = & $field 'Status'
        $helperError = & $field 'Error'
        $backup = [string] (& $field 'BackupFile')
        # Exakt $true (bool): ein Text wie 'true' oder ein fehlendes Feld ist kein Erfolg.
        $removed = $status -eq 'Completed' -and -not $helperError -and (& $field 'Removed') -is [bool] -and (& $field 'Removed')
        $atPlannedPlace = [bool] $backup -and [string]::Equals($backup, $Plan.BackupFile, [StringComparison]::OrdinalIgnoreCase)
        # Gibt es den Schlüssel noch? $true, $false oder $null (nicht lesbar: zählt nie als „weg“).
        $probe = { try { [bool] (Test-MachineRegistryKeyPresent -RegistryKey $Plan.RegistryKey) } catch { $null } }
        if ($status -eq 'ElevationDenied') {
            # Der Helfer lief nicht: nichts geändert, keine Sicherung.
            $Result.Result = 'ElevationDenied'
            $Result.Message = $helperError
            $Result.PresentAfter = $true
            $Result.BackupFile = $null
        }
        elseif (-not $removed) {
            $present = & $probe
            $Result.PresentAfter = $present -ne $false
            $Result.Result = 'Failed'
            $Result.Message = if ($helperError) { $helperError } else { New-InventoryMessage HelperResultUnreadable }
            # Die Sicherung bleibt nur, wenn der Helfer sie nennt (Löschen gescheitert, nachdem sie stand).
            $Result.BackupFile = if ($atPlannedPlace) { $Plan.BackupFile }
            if ($atPlannedPlace -and (& $field 'ErrorCode') -ceq 'RemoveEntryDeleteFailed') {
                $Result.Message = New-InventoryMessage RemoveEntryDeleteFailedBackupKept $Plan.BackupFile
            }
            elseif ($status -ne 'Completed' -and $present -eq $false -and (Test-Path -LiteralPath $Plan.BackupFile -PathType Leaf)) {
                # Antwort verloren (Zeitüberschreitung, Pipe), der Helfer hat aber offenbar gesichert und entfernt: ehrlich
                # als unklar melden, mit dem Ort der Sicherung, nie als Erfolg.
                $Result.Message = New-InventoryMessage RemoveEntryResultUnclear $Plan.BackupFile
                $Result.BackupFile = $Plan.BackupFile
            }
        }
        elseif (-not $atPlannedPlace) {
            $Result.PresentAfter = (& $probe) -ne $false
            $Result.Result = 'Failed'
            $Result.Message = New-InventoryMessage RemoveEntryBackupUnexpected $backup
            $Result.BackupFile = $null
        }
        else {
            $present = & $probe
            $Result.PresentAfter = $present -ne $false
            if ($present -eq $false) {
                $Result.Result = 'Succeeded'
                $Result.Message = New-InventoryMessage RemoveEntryDoneMachine $Plan.BackupFile
            }
            else {
                $Result.Result = 'Failed'
                $Result.Message = New-InventoryMessage RemoveEntryDeleteFailedBackupKept $Plan.BackupFile
            }
        }
    }
    catch {
        # Der Helfer ließ sich nicht starten oder warf; eine Sicherung gibt es nur, wenn sie am geplanten Ort liegt.
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage RemoveEntryDeleteFailed $_.Exception.Message
        $Result.BackupFile = if (Test-Path -LiteralPath $Plan.BackupFile -PathType Leaf) { $Plan.BackupFile }
    }
    $Result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $Result)
    $Result
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
        if ($exit -eq 0 -and -not $problem) {
            # Die Begleitdatei kommt vor dem Löschen; ohne sie ließe sich später nichts prüfen oder zurückspielen.
            try { Write-RegistryBackupSidecar -File $Plan.BackupFile -ActionId $Plan.ActionId -Name $Plan.Name -NativeKey $Plan.NativeKey -Scope $Plan.Scope -Reasons $Plan.Reasons }
            catch { $problem = 'MetadataWrite' }
        }
        if ($exit -ne 0 -or $problem) {
            # Unbrauchbare Sicherung nicht liegen lassen; der Schlüssel bleibt unberührt.
            Remove-Item -LiteralPath $Plan.BackupFile, (Get-RegistryBackupSidecarPath $Plan.BackupFile) -Force -ErrorAction SilentlyContinue
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
