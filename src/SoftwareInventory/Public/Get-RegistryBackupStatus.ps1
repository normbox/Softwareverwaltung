function Get-RegistryBackupStatus {
    <#
    .SYNOPSIS
        Zustand des Admin-Ordners für HKLM-Sicherungen: vorhanden, lesbar, und wie viele Sicherungen abgelaufen sind.
    .DESCRIPTION
        Nur lesend, ohne Adminrechte. MachineFolderState: Missing (noch nie eine HKLM-Sicherung), Readable oder
        Unreadable (die Rechte erlauben das Lesen nicht; dann fehlen die HKLM-Sicherungen in Get-RegistryBackup).
        ExpiredMachineCount: HKLM-Sicherungen älter als 365 Tage; aufräumen mit Clear-ExpiredRegistryBackup (UAC).
        Sicherungen des Benutzers räumt die Selbstbereinigung beim Start ohnehin auf.
    .EXAMPLE
        Get-RegistryBackupStatus
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.RegistryBackupStatus')]
    param()

    $folder = Get-RegistryBackupMachineDirectory
    $state = 'Missing'
    $expired = 0
    if (Test-Path -LiteralPath $folder -PathType Container) {
        try {
            $null = Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction Stop | Select-Object -First 1
            $state = 'Readable'
            $expired = @(Get-RegistryBackupFile | Where-Object { $_.BackupScope -eq 'Machine' -and (Test-RegistryBackupExpired -File $_) }).Count
        }
        catch { $state = 'Unreadable' }
    }
    [pscustomobject] @{
        PSTypeName          = 'SoftwareInventory.RegistryBackupStatus'
        MachineFolder       = $folder
        MachineFolderState  = $state
        ExpiredMachineCount = $expired
        RetentionDays       = $script:RegistryBackupRetentionDays
    }
}
