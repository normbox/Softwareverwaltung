function Get-InventorySetting {
    <#
    .SYNOPSIS
        Zeigt die Einstellungen: welche Quellen, Nutzungsspuren und Scan-Bereiche aktiviert sind.
    .DESCRIPTION
        Gespeichert unter %APPDATA%\SoftwareInventory\settings.json. Ohne Datei ist alles aus.
    .EXAMPLE
        (Get-InventorySetting).Sources
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.Setting')]
    param()

    Read-InventorySetting
}
