function Get-RegistryBackup {
    <#
    .SYNOPSIS
        Listet die Registry-Sicherungen, die „Eintrag entfernen“ angelegt hat: die des Benutzers (logs\registry-backup)
        und die für alle Benutzer (Admin-Ordner Program Files\Softwareverwaltung\RegistryBackup).
    .DESCRIPTION
        HKCU: <ActionId>_<Name>.reg und .json. HKLM: <ActionId>.reg und .json, vom erhöhten Helfer angelegt; der Ordner
        ist für Benutzer lesbar, die Liste braucht keine Adminrechte. Die Liste zeigt Name, Zeitpunkt (UTC), Schlüssel,
        Gründe und Bereich (Scope User/Machine). CanRestore sagt, ob die Vorprüfung das Zurückspielen zulässt (bei HKLM
        prüft der Helfer erneut); sonst nennt Problem den Grund (Code) und ProblemMessage die Meldung dazu. Elevated:
        Zurückspielen und Löschen brauchen Administratorrechte. Expired: älter als 365 Tage. Ältere Sicherungen ohne
        .json (IsLegacy) lassen sich nur löschen, nicht zurückspielen (MetadataMissing). Nur lesend; neueste zuerst.
    .PARAMETER Id
        Nur die Sicherung mit dieser Kennung (GUID aus dem Dateinamen).
    .EXAMPLE
        Get-RegistryBackup | Format-Table CreatedAt, Scope, Name, CanRestore
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.RegistryBackup')]
    param([string] $Id)

    $files = @(Get-RegistryBackupFile)
    if ($Id) { $files = @($files | Where-Object { (Get-RegistryBackupId $_.Name) -eq $Id.ToLowerInvariant() }) }
    $backups = @(foreach ($file in $files) { Get-RegistryBackupInfo -File $file })
    foreach ($backup in $backups | Sort-Object CreatedAt -Descending) { $backup }
}
