function Restore-RegistryBackup {
    <#
    .SYNOPSIS
        Spielt eine Registry-Sicherung zurück (reg import): Einträge des Benutzers (HKCU) direkt, Einträge für alle
        Benutzer (HKLM) über den erhöhten Helfer (UAC-Abfrage, Operation RestoreRegistryBackup).
    .DESCRIPTION
        Vor dem Zurückspielen prüft das Modul streng: Die .json-Begleitdatei muss vorhanden und lesbar sein
        (sonst BackupMetadataMissing/BackupMetadataInvalid, z. B. bei älteren Sicherungen), die .reg-Datei darf
        genau einen Hauptschlüssel enthalten (der aus der .json, direkt unter einem Uninstall-Zweig des
        passenden Bereichs: Benutzer im Benutzerordner, alle Benutzer im Admin-Ordner); jeder weitere Schlüsselkopf muss ein Unterschlüssel davon sein; keine Löschzeilen. Schlägt
        eine Prüfung fehl, wird nichts importiert, die Aktion wird protokolliert und ein Grund-Code geliefert.
        Existiert der Schlüssel inzwischen wieder, wird ebenfalls nichts importiert (RestoreKeyExists).
        Die Datei wird genau einmal gelesen, dieser Inhalt geprüft, in eine eigene temporäre Datei geschrieben
        und genau diese importiert (kein Austausch zwischen Prüfung und Import); die temporäre Datei wird danach
        gelöscht. Die Sicherung bleibt erhalten.
        HKLM: Das Modul prüft vorab dasselbe ohne Adminrechte (der Admin-Ordner ist lesbar); der Helfer findet die Datei
        nur über die Kennung im Admin-Ordner, prüft alles erneut und importiert genau die geprüften Bytes. Erfolg nur,
        wenn der Helfer das meldet, der von ihm gemeldete Schlüssel der bestätigte ist und dieser danach in der
        64-Bit-Ansicht existiert. Ein Wiederherstellungspunkt
        wird nie angelegt. Jede Aktion wird protokolliert (Action RestoreBackup); -WhatIf liefert den Plan.
    .PARAMETER InputObject
        Kennung (GUID) oder ein Objekt von Get-RegistryBackup.
    .PARAMETER ConfirmedCommandLine
        CommandLine aus dem -WhatIf-Ergebnis (die Kennung). Weicht sie ab, wird nichts zurückgespielt (Cancelled).
    .PARAMETER ConfirmedActionId
        ActionId aus dem -WhatIf-Ergebnis: Die Ausführung nutzt genau diese Kennung (Protokoll). Keine GUID oder schon
        benutzt: nichts wird ausgeführt (Cancelled, ActionIdInvalid bzw. ActionIdUsed). Ohne Angabe eine neue Kennung.
    .PARAMETER LogNotExecutable
        Für Oberflächen, die mit -WhatIf planen: Ist die Aktion nicht ausführbar, wird das trotzdem protokolliert.
    .EXAMPLE
        Get-RegistryBackup | Where-Object CanRestore | Select-Object -First 1 | Restore-RegistryBackup -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.ActionResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [object[]] $InputObject,

        [string] $ConfirmedCommandLine,

        [string] $ConfirmedActionId,

        [switch] $LogNotExecutable
    )

    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            $plan = New-RestoreBackupPlan -Id (Get-BackupActionInput $item)
            Set-ConfirmedActionId -Plan $plan -ActionId (Resolve-ConfirmedActionId $ConfirmedActionId)
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
            $description = if ($plan.Elevated) { New-InventoryMessage PlanRestoreBackupMachine $plan.Name, $plan.NativeKey } else { New-InventoryMessage PlanRestoreBackup $plan.Name, $plan.NativeKey }
            if (-not $PSCmdlet.ShouldProcess($plan.Name, $description.Text)) {
                $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
                $result.Message = if ($WhatIfPreference) { $description } else { New-InventoryMessage NotConfirmed }
                $result
                continue
            }
            if ($plan.Elevated) { Invoke-RestoreMachineBackupPlan -Plan $plan -Result $result }
            else { Invoke-RestoreBackupPlan -Plan $plan -Result $result }
        }
    }
}

function Test-RegistryKeyPresent {
    # Gibt es den Schlüssel (nativer Pfad wie HKEY_CURRENT_USER\...)? LiteralPath: keine Platzhalter.
    # HKLM in der 64-Bit-Ansicht wie der Helfer (WOW6432Node wörtlich).
    param([string] $NativeKey)
    if ($NativeKey -match '^(?i:HKEY_LOCAL_MACHINE\\)') { return Test-MachineRegistryKeyPresent -RegistryKey $NativeKey }
    Test-Path -LiteralPath "Registry::$NativeKey"
}

function Invoke-RestoreMachineBackupPlan {
    # HKLM-Sicherung über den Helfer zurückspielen; Erfolg nur, wenn der Schlüssel danach da ist. Protokolliert Start und Ende.
    param($Plan, $Result)
    $Result | Add-Member -NotePropertyName BackupFile -NotePropertyValue $Plan.BackupFile -Force
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $Result)
    try {
        $run = Invoke-BackupHelper -HelperPlan @{ Operation = 'RestoreRegistryBackup'; BackupId = $Plan.BackupId }
        $present = if ($run.Status -eq 'Completed') { try { [bool] (Test-RegistryKeyPresent $Plan.NativeKey) } catch { $false } } else { $false }
        $Result.PresentAfter = $present
        # Der Helfer liest die .json selbst: Hat er einen anderen Schlüssel zurückgespielt als den bestätigten (die .json
        # wurde nach der Bestätigung geändert), ist das kein Erfolg, auch wenn der bestätigte Schlüssel zufällig existiert.
        $sameKey = $run.NativeKey -is [string] -and [string]::Equals($run.NativeKey, [string] $Plan.NativeKey, [StringComparison]::OrdinalIgnoreCase)
        Complete-BackupHelperResult -Result $Result -Run $run -Verified ($present -and $sameKey) -SuccessMessage (New-InventoryMessage RestoreBackupDone $Plan.NativeKey)
    }
    catch {
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage RestoreBackupFailed $_.Exception.Message
    }
    $Result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $Result)
    $Result
}

function New-RestoreBackupPlan {
    # Plan mit Prüfung von Begleitdatei und Inhalt; Result gesetzt, wenn nichts zurückzuspielen ist.
    param([string] $Id)
    $file = Find-RegistryBackupFile -Id $Id
    if (-not $file) {
        $plan = New-BackupActionPlan -Action RestoreBackup -Name $Id -BackupId $Id -NativeKey $null -BackupFile $null -Method RegistryImport
        $plan.State.Present = $false
        $plan.Result = 'NotInstalled'; $plan.Message = New-InventoryMessage BackupNotFound
        return [pscustomobject] $plan
    }
    $info = Get-RegistryBackupInfo -File $file
    $plan = New-BackupActionPlan -Action RestoreBackup -Name $info.Name -BackupId $info.Id -NativeKey $info.NativeKey -BackupFile $file.FullName -Method RegistryImport -Scope $info.Scope
    if ($info.Problem) {
        $plan.Result = 'Unsupported'; $plan.Message = $info.ProblemMessage
    }
    elseif (Test-RegistryKeyPresent $info.NativeKey) {
        $plan.State.Present = $true
        $plan.Result = 'Unsupported'; $plan.Message = New-InventoryMessage RestoreKeyExists $info.NativeKey
    }
    else { $plan.State.Present = $false }
    [pscustomobject] $plan
}

function Invoke-RestoreBackupPlan {
    # Datei einmal lesen, prüfen, genau diesen Inhalt in eine eigene temporäre Datei schreiben und importieren.
    param($Plan, $Result)
    $Result | Add-Member -NotePropertyName BackupFile -NotePropertyValue $Plan.BackupFile -Force
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $Result)
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) "SoftwareInventory-restore-$($Plan.ActionId).reg"
    try {
        $content = Get-RegistryBackupText -File $Plan.BackupFile
        $sidecar = Read-RegistryBackupSidecar -File $Plan.BackupFile
        $problem = if ($sidecar.Problem) { $sidecar.Problem }
        elseif ($sidecar.Data.NativeKey -cne $Plan.NativeKey) { 'MetadataInvalid' }
        elseif ($content.Problem) { $content.Problem }
        else { Test-RegistryBackupContent -Text $content.Text -NativeKey $Plan.NativeKey }
        if ($problem) {
            $Result.Result = 'Failed'
            $Result.Message = New-InventoryMessage "Backup$problem"
        }
        elseif (Test-RegistryKeyPresent $Plan.NativeKey) {
            $Result.Result = 'Failed'
            $Result.Message = New-InventoryMessage RestoreKeyExists $Plan.NativeKey
        }
        else {
            $stream = [System.IO.File]::Open($temp, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try { $stream.Write($content.Bytes, 0, $content.Bytes.Length) }
            finally { $stream.Dispose() }
            $exit = Invoke-RegImport -File $temp
            $Result.ExitCode = $exit
            $present = Test-RegistryKeyPresent $Plan.NativeKey
            $Result.PresentAfter = $present
            $ok = $exit -eq 0 -and $present
            $Result.Result = if ($ok) { 'Succeeded' } else { 'Failed' }
            $Result.Message = if ($ok) { New-InventoryMessage RestoreBackupDone $Plan.NativeKey } else { New-InventoryMessage RestoreBackupFailed "Exit $exit" }
        }
    }
    catch {
        $Result.Result = 'Failed'
        $Result.Message = New-InventoryMessage RestoreBackupFailed $_.Exception.Message
    }
    finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    $Result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $Result)
    $Result
}
