function Get-RegistryBackup {
    <#
    .SYNOPSIS
        Listet die Registry-Sicherungen, die „Eintrag entfernen“ angelegt hat (logs\registry-backup).
    .DESCRIPTION
        Je Sicherung gibt es <ActionId>_<Name>.reg (reg export) und <ActionId>_<Name>.json (Name, Schlüssel,
        Gründe als Codes). Die Liste zeigt Name, Zeitpunkt (UTC), Schlüssel und Gründe. CanRestore sagt, ob
        Restore-RegistryBackup die Sicherung zurückspielen würde; sonst nennt Problem den Grund (Code) und
        ProblemMessage die Meldung dazu. Ältere Sicherungen ohne .json (IsLegacy) lassen sich nur löschen,
        nicht zurückspielen (MetadataMissing). Nur lesend; neueste zuerst. Sicherungen werden 365 Tage
        aufbewahrt.
    .PARAMETER Id
        Nur die Sicherung mit dieser Kennung (GUID aus dem Dateinamen).
    .EXAMPLE
        Get-RegistryBackup | Format-Table CreatedAt, Name, CanRestore
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.RegistryBackup')]
    param([string] $Id)

    $directory = Get-RegistryBackupDirectory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
    $files = @(Get-ChildItem -LiteralPath $directory -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ieq '.reg' -and (Get-RegistryBackupId $_.Name) })
    if ($Id) { $files = @($files | Where-Object { (Get-RegistryBackupId $_.Name) -eq $Id.ToLowerInvariant() }) }
    $backups = @(foreach ($file in $files) { Get-RegistryBackupInfo -File $file })
    foreach ($backup in $backups | Sort-Object CreatedAt -Descending) { $backup }
}
