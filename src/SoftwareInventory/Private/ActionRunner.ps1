# Ausführung eines Plans (New-ActionPlan), Prüfung des Zustands danach und Protokoll.
# Gemeinsamer Kern von Update-Software und Uninstall-Software.

# Nach dem Ende des Programms wird bis zu 60 s geprüft, ob der Zustand passt: Viele Inno- und
# NSIS-Deinstallationsprogramme starten einen Kindprozess und kehren sofort zurück.
$script:VerifyTimeoutSeconds = 60
$script:VerifyIntervalSeconds = 2

$script:RestorePointType = @{ Update = [uint32] 0; Uninstall = [uint32] 1 }   # APPLICATION_INSTALL / _UNINSTALL

function Invoke-AppxRemoval {
    # Store-Apps gelten pro Benutzer; daher immer im aktuellen Benutzerkontext, ohne Adminrechte.
    param([Parameter(Mandatory)] [string] $PackageFullName)
    Remove-AppxPackage -Package $PackageFullName -ErrorAction Stop
}

function Test-ActionStateReached {
    param([string] $Action, $Before, $After)
    if ($Action -eq 'Uninstall') { return -not $After.Present }
    if (-not $After.Present -or -not $After.Version) { return $false }
    $before = if ($Before.Identity -eq 'Winget' -or -not $Before.Version) { $Before.WingetVersion } else { $Before.Version }
    if (-not $before) { $before = $Before.Version }
    (Compare-SoftwareVersion $before $After.Version) -eq -1
}

function Wait-ActionState {
    # Liest den Zustand wiederholt neu, bis er passt oder die Wartezeit um ist.
    param([string] $Action, $Record, $Before, [bool] $Poll)
    $deadline = [datetime]::UtcNow.AddSeconds($(if ($Poll) { $script:VerifyTimeoutSeconds } else { 0 }))
    while ($true) {
        $after = Get-InstalledState -Record $Record
        if ((Test-ActionStateReached -Action $Action -Before $Before -After $after) -or [datetime]::UtcNow -ge $deadline) { return $after }
        Start-Sleep -Seconds $script:VerifyIntervalSeconds
    }
}

function New-ActionResult {
    # Rückgabeobjekt mit festem Typnamen; die App liest es ohne Textauswertung.
    param($Plan)
    [pscustomobject] [ordered]@{
        PSTypeName          = 'SoftwareInventory.ActionResult'
        ActionId            = $Plan.ActionId
        Action              = $Plan.Action
        Name                = $Plan.Name
        WingetId            = $Plan.WingetId
        WingetSource        = $Plan.WingetSource
        RegistryKey         = $Plan.RegistryKey
        ProductCode         = $Plan.ProductCode
        PackageFullName     = $Plan.PackageFullName
        Scope               = $Plan.Scope
        Method              = $Plan.Method
        FilePath            = $Plan.FilePath
        Arguments           = $Plan.Arguments
        CommandLine         = $Plan.CommandLine
        Elevated            = $Plan.Elevated
        Result              = $Plan.Result
        ExitCode            = $null
        ExitCodeHex         = $null
        Message             = $Plan.Message
        Output              = $null
        InstallerLog        = $null
        VersionBefore       = $Plan.State.Version
        VersionAfter        = $null
        PresentBefore       = $Plan.State.Present
        PresentAfter        = $null
        RestorePoint        = 'NotRequested'
        RestorePointMessage = $null
        VendorUrl           = $Plan.VendorUrl
        NextMethod          = $Plan.NextMethod
        StartedAt           = [datetime]::UtcNow
        CompletedAt         = $null
    }
}

function ConvertTo-ActionLogData {
    # Felder fürs Protokoll; von der Ausgabe nur die letzten 20 Zeilen.
    param($Result)
    $data = [ordered]@{}
    foreach ($p in $Result.PSObject.Properties) {
        if ($p.Name -in 'StartedAt', 'CompletedAt') { $data[$p.Name] = if ($p.Value) { ([datetime] $p.Value).ToString('o') } else { $null }; continue }
        $data[$p.Name] = $p.Value
    }
    if ($data.Output) { $data.Output = (@($data.Output -split "`n") | Select-Object -Last 20) -join "`n" }
    $data
}

function Get-RestorePointDescription {
    param($Plan)
    $verb = New-InventoryMessage "ActionVerb$($Plan.Action)"
    $text = (New-InventoryMessage RestorePointName $verb, $Plan.Name).Text
    if ($text.Length -gt 64) { $text.Substring(0, 64) } else { $text }
}

function Invoke-ActionPlan {
    <#
    .SYNOPSIS
        Führt einen ausführbaren Plan aus, prüft den Zustand danach und protokolliert.
    .OUTPUTS
        SoftwareInventory.ActionResult
    #>
    param(
        [Parameter(Mandatory)] $Plan,
        [Parameter(Mandatory)] $Record,
        [int] $TimeoutMinutes = 60
    )

    $result = New-ActionResult $Plan
    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $result)
    $timeout = $TimeoutMinutes * 60
    $outcome = $null
    $failure = $null

    try {
        # Wiederherstellungspunkt für Aktionen ohne Adminrechte: eigener kurzer UAC-Aufruf.
        if ($Plan.RestorePoint -and -not $Plan.Elevated) {
            $rp = Start-ElevatedHelper -TimeoutSeconds 600 -HelperPlan @{
                FilePath = $null; RestorePoint = $true
                RestorePointDescription = Get-RestorePointDescription $Plan; RestorePointType = $script:RestorePointType[$Plan.Action]
            }
            if ($rp.Status -eq 'Completed') {
                $result.RestorePoint = $rp.RestorePoint
                $result.RestorePointMessage = $rp.RestorePointMessage
            }
            else {
                $result.RestorePoint = 'Failed'
                $result.RestorePointMessage = New-InventoryMessage RestorePointContinueWithout (, $rp.Error)
            }
        }

        if ($Plan.Method -eq 'Appx') {
            try {
                Invoke-AppxRemoval -PackageFullName $Plan.PackageFullName
                $outcome = @{ Outcome = 'Success'; Message = (New-InventoryMessage AppxRemoved) }
            }
            catch {
                $outcome = @{ Outcome = 'Failed'; Message = (New-InventoryMessage AppxRemoveFailed $_.Exception.Message) }
            }
        }
        else {
            $helperPlan = @{
                FilePath = $Plan.FilePath; Arguments = $Plan.Arguments; MsiLog = $Plan.MsiLog; Elevate = [bool] $Plan.Elevated
                RestorePoint = [bool] ($Plan.RestorePoint -and $Plan.Elevated)
                RestorePointDescription = Get-RestorePointDescription $Plan; RestorePointType = $script:RestorePointType[$Plan.Action]
            }
            $run = Start-ElevatedHelper -HelperPlan $helperPlan -TimeoutSeconds $timeout -NoElevation:(-not $Plan.Elevated)
            if ($Plan.Elevated -and $run.ContainsKey('RestorePoint') -and $run.RestorePoint -ne 'NotRequested') {
                $result.RestorePoint = $run.RestorePoint
                $result.RestorePointMessage = $run.RestorePointMessage
            }
            if ($run.ContainsKey('Output')) { $result.Output = Protect-SecretText $run.Output }
            if ($run.ContainsKey('InstallerLog')) { $result.InstallerLog = $run.InstallerLog }

            if ($run.Status -eq 'ElevationDenied') { $failure = @('ElevationDenied', $run.Error) }
            elseif ($run.Status -ne 'Completed') { $failure = @('Failed', $run.Error) }
            elseif ($run.Error) { $failure = @('Failed', $run.Error) }
            elseif ($run.TimedOut) { $failure = @('Timeout', (New-InventoryMessage ActionTimeout $TimeoutMinutes)) }
            else {
                $result.ExitCode = [long] $run.ExitCode
                $outcome = ConvertFrom-ActionExitCode $run.ExitCode
                $result.ExitCodeHex = $outcome.Code
            }
        }
    }
    catch {
        $failure = @('Failed', (New-InventoryMessage UnexpectedError $_.Exception.Message))
    }

    $poll = $outcome -and $outcome.Outcome -in 'Success', 'SuccessReboot'
    $after = Wait-ActionState -Action $Plan.Action -Record $Record -Before $Plan.State -Poll $poll
    $result.VersionAfter = $after.Version
    $result.PresentAfter = $after.Present
    $reached = Test-ActionStateReached -Action $Plan.Action -Before $Plan.State -After $after

    if ($failure) {
        $result.Result, $result.Message = $failure
    }
    else {
        switch ($outcome.Outcome) {
            'Success' {
                if ($reached) { $result.Result = 'Succeeded'; $result.Message = $outcome.Message }
                else {
                    $result.Result = 'NotVerified'
                    $result.Message = if ($Plan.Action -eq 'Uninstall') { New-InventoryMessage NotVerifiedUninstall }
                    else { New-InventoryMessage NotVerifiedUpdate }
                }
            }
            'SuccessReboot' { $result.Result = 'SucceededRebootRequired'; $result.Message = $outcome.Message }
            'Cancelled' { $result.Result = 'Cancelled'; $result.Message = $outcome.Message }
            'NotInstalled' { $result.Result = 'NotInstalled'; $result.Message = $outcome.Message }
            'NoUpdate' { $result.Result = 'NoUpdateAvailable'; $result.Message = $outcome.Message }
            default { $result.Result = 'Failed'; $result.Message = $outcome.Message }
        }
    }
    if ($result.Result -in 'Failed', 'NotVerified', 'Timeout' -and $result.NextMethod) {
        $result.Message = New-InventoryMessage WithNextMethod $result.Message, $result.NextMethod
    }

    # Installer-Log nur bei Problemen aufheben (komprimiert), sonst gar nicht erst speichern.
    if ($result.InstallerLog -and $result.Result -notin 'Succeeded', 'SucceededRebootRequired') {
        $directory = Get-InstallerLogDirectory
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $path = Join-Path $directory "$($result.ActionId).log"
        Set-Content -LiteralPath $path -Value $result.InstallerLog -Encoding utf8NoBOM
        $result.InstallerLog = Complete-InstallerLog -Path $path -Keep $true
    }
    else {
        $result.InstallerLog = $null
    }

    $result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result)
    $result
}

function Resolve-SoftwareAction {
    <#
    .SYNOPSIS
        Gemeinsame Vorbereitung von Update-Software und Uninstall-Software für einen Datensatz.
    .OUTPUTS
        @{ Record; Plan; Result; Description } – Result ist gesetzt, wenn nichts auszuführen ist
        (bereits protokolliert); sonst fragt der Aufrufer ShouldProcess mit Description.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Update', 'Uninstall')] [string] $Action,
        [Parameter(Mandatory)] $InputObject,
        [string] $Method = 'Auto',
        [bool] $RestorePoint,
        # Befehl, den der Benutzer bestätigt hat. Weicht der neu ermittelte ab, wird nichts ausgeführt.
        [string] $ConfirmedCommandLine
    )

    $record = Get-ActionRecord $InputObject
    if (-not $record -or -not $record.PSObject.Properties['Name']) {
        Write-Error (Get-LocalizedString 'ErrorNotInventoryRecord')
        return $null
    }

    $plan = New-ActionPlan -Action $Action -Record $record -Method $Method -RestorePoint $RestorePoint
    if (-not $plan.Result -and $ConfirmedCommandLine -and $plan.CommandLine -cne $ConfirmedCommandLine) {
        $plan.Result = 'Cancelled'
        $plan.Message = New-InventoryMessage CommandChanged $plan.CommandLine
    }
    if ($plan.Result) {
        # Nicht ausführbar: nichts gestartet, aber protokolliert (außer bei -WhatIf).
        $result = New-ActionResult $plan
        $result.CompletedAt = $result.StartedAt
        if (-not $WhatIfPreference) { Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result) }
        return @{ Record = $record; Plan = $plan; Result = $result; Description = $null }
    }

    # Description ist eine Meldung; ShouldProcess bekommt ihren Text.
    $rights = New-InventoryMessage $(if ($plan.Elevated) { 'PlanRightsElevated' } else { 'PlanRightsNormal' })
    $rp = if ($RestorePoint) { New-InventoryMessage PlanRestorePointFirst } else { '' }
    $verb = New-InventoryMessage "ActionVerb$Action"
    @{ Record = $record; Plan = $plan; Result = $null; Description = (New-InventoryMessage PlanDescription $verb, $plan.Method, $rights, $rp, $plan.CommandLine) }
}

function New-DeclinedActionResult {
    # Ergebnis, wenn ShouldProcess nein sagt: bei -WhatIf „Planned“ (für den Bestätigungsdialog), sonst „Cancelled“.
    param($Prepared)
    $result = New-ActionResult $Prepared.Plan
    $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
    $result.Message = if ($WhatIfPreference) { $Prepared.Description } else { New-InventoryMessage NotConfirmed }
    $result.RestorePoint = if ($Prepared.Plan.RestorePoint) { 'Planned' } else { 'NotRequested' }
    $result
}
