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
        KeyPresent: Der Eintrag existiert schon wieder (ohne UAC gelesen); dann ist CanRestore $false. Gibt es mehrere
        Sicherungen zum selben Schlüssel, ist die neueste IsLatest und alle älteren NewerExists; ältere bleiben
        zurückspielbar.
    .PARAMETER Id
        Nur die Sicherung mit dieser Kennung (GUID aus dem Dateinamen).
    .EXAMPLE
        Get-RegistryBackup | Format-Table CreatedAt, Scope, Name, CanRestore
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.RegistryBackup')]
    param([string] $Id)

    $backups = @(foreach ($file in Get-RegistryBackupFile) { Get-RegistryBackupInfo -File $file })
    # Mehrere Sicherungen zum selben Schlüssel (Groß-/Kleinschreibung egal; HKCU und HKLM unterscheidet die Wurzel):
    # die neueste IsLatest, alle älteren NewerExists. Über alle Sicherungen, auch wenn nur eine (-Id) ausgegeben wird.
    $groups = $backups | Where-Object { $_.NativeKey } | Group-Object { ([string] $_.NativeKey).ToUpperInvariant() } | Where-Object Count -GT 1
    foreach ($group in $groups) {
        $ordered = @($group.Group | Sort-Object @{ Expression = 'CreatedAt'; Descending = $true }, @{ Expression = 'Id'; Descending = $false })
        $ordered[0].IsLatest = $true
        foreach ($older in $ordered | Select-Object -Skip 1) { $older.NewerExists = $true }
    }
    if ($Id) { $backups = @($backups | Where-Object { $_.Id -eq $Id.ToLowerInvariant() }) }
    foreach ($backup in $backups | Sort-Object CreatedAt -Descending) { $backup }
}
