function Install-WingetPackageManager {
    <#
    .SYNOPSIS
        Installiert oder repariert winget (App Installer) für das angemeldete Benutzerkonto.
    .DESCRIPTION
        Ruft Repair-WinGetPackageManager -Latest aus Microsoft.WinGet.Client auf. Das lädt die neueste
        Version von App Installer bei Microsoft herunter und installiert sie nur für dieses Konto,
        ohne Administratorrechte. Erfolg wird mit Test-WingetAvailability geprüft. Jede Ausführung
        wird protokolliert (Get-ActionLog -Action InstallWinget); -WhatIf liefert Result Planned.
    .EXAMPLE
        Install-WingetPackageManager -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('SoftwareInventory.ActionResult')]
    param()

    $before = Test-WingetAvailability
    $plan = [pscustomobject] [ordered]@{
        ActionId = [guid]::NewGuid().ToString(); Action = 'InstallWinget'; Name = 'winget (App Installer)'
        WingetId = $null; WingetSource = $null; RegistryKey = $null; ProductCode = $null; PackageFullName = $null
        Scope = 'User'; Method = 'RepairWinGetPackageManager'; FilePath = $null; Arguments = '-Latest'
        CommandLine = 'Repair-WinGetPackageManager -Latest'; Elevated = $false; RestorePoint = $false
        Result = $null; Message = $null; NextMethod = $null; VendorUrl = $null
        State = @{ Version = $before.ModuleVersion; Present = $before.CliAvailable }
    }
    $result = New-ActionResult $plan
    $description = 'Lädt die neueste Version von App Installer (winget) bei Microsoft herunter und installiert sie für dieses Benutzerkonto, ohne Administratorrechte: ' + $plan.CommandLine

    if (-not (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue)) {
        $result.Result = 'Unsupported'
        $result.Message = 'Das PowerShell-Modul Microsoft.WinGet.Client fehlt; winget lässt sich so nicht installieren. App Installer gibt es im Microsoft Store.'
        $result.VendorUrl = 'https://apps.microsoft.com/detail/9NBLGGH4NNS1'
        $result.CompletedAt = $result.StartedAt
        if (-not $WhatIfPreference) { Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result) }
        return $result
    }
    if (-not $PSCmdlet.ShouldProcess($plan.Name, $description)) {
        $result.Result = if ($WhatIfPreference) { 'Planned' } else { 'Cancelled' }
        $result.Message = if ($WhatIfPreference) { $description } else { 'Nicht bestätigt; es wurde nichts ausgeführt.' }
        return $result
    }

    Write-ActionLogEntry -Phase Started -Data (ConvertTo-ActionLogData $result)
    try {
        $output = Invoke-WingetRepair
        $result.Output = Protect-SecretText (($output | Out-String).Trim())
        $after = Test-WingetAvailability
        $result.PresentAfter = $after.CliAvailable
        $result.VersionAfter = $after.ModuleVersion
        if ($after.Available) { $result.Result = 'Succeeded'; $result.Message = 'winget ist installiert und nutzbar.' }
        else { $result.Result = 'NotVerified'; $result.Message = "Repair-WinGetPackageManager ist durchgelaufen, winget ist aber noch nicht nutzbar: $($after.Message)" }
    }
    catch {
        $result.Result = 'Failed'
        $result.Message = "winget konnte nicht installiert werden: $(Protect-SecretText $_.Exception.Message)"
    }
    $result.CompletedAt = [datetime]::UtcNow
    Write-ActionLogEntry -Phase Completed -Data (ConvertTo-ActionLogData $result)
    $result
}

function Invoke-WingetRepair {
    # Eigene Funktion, damit Tests den Download ersetzen können.
    Repair-WinGetPackageManager -Latest -ErrorAction Stop
}
