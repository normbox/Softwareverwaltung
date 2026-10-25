# Felder eines Datensatzes in fester Reihenfolge (ohne Name und Sources).
# Neue Felder hier ergänzen; Get-InventorySnapshot füllt sie bei älteren Snapshots mit $null auf.
$script:RecordFields = @(
    'Publisher'
    'Version'
    'InstallType'           # MSI, EXE, MSIX, Winget, Portable
    'Scope'                 # Machine, User
    'Architecture'          # X64, X86, Arm64, Neutral
    'WingetId'
    'WingetSource'
    'AvailableVersion'
    'ProductCode'
    'RegistryKey'
    'PackageFullName'
    'PackageFamilyName'
    'InstallLocation'
    'InstallDate'           # yyyy-MM-dd
    'UninstallString'
    'QuietUninstallString'
    'DisplayIcon'           # Pfad zur Haupt-.exe bzw. zum Symbol (Registry)
    'Companions'            # PackageFullName zugeordneter Begleitpakete (z. B. Kontextmenü als Sparse Package)
    # Nur portable Programme:
    'FilePath'
    'CopyPaths'             # weitere Fundorte identischer Kopien
    'Sha256'                # nur im gründlichen Scan
    'SignatureStatus'       # Valid, NotSigned, HashMismatch, NotTrusted, ...
    'Signer'
    'Evidence'              # FileScan, UserAssist, Process, Autostart, ScheduledTask
    'LastRun'               # ISO 8601 (UTC), nur aus UserAssist
    'RunCount'
    'Flags'                 # Unsigned, InvalidSignature, InDownloadsOrTemp, Autostart, MultipleVersions
)

function New-SoftwareRecord {
    <#
    .SYNOPSIS
        Erzeugt einen leeren Inventar-Datensatz mit allen Feldern des Schemas.
    .DESCRIPTION
        Alle Quellen bauen ihre Datensätze über diese Funktion, damit jedes Objekt
        dieselben Felder hat. Das Schema ist in docs/INVENTAR-SCHEMA.md beschrieben.
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Registry', 'Winget', 'Appx', 'Portable')] [string] $Source,
        [hashtable] $Property = @{}
    )

    $record = [ordered]@{
        PSTypeName = 'SoftwareInventory.SoftwareRecord'
        Name       = $Name
        Sources    = [string[]] @($Source)
    }
    foreach ($field in $script:RecordFields) { $record[$field] = $null }

    foreach ($key in $Property.Keys) {
        if (-not $record.Contains($key) -or $key -in 'PSTypeName', 'Name', 'Sources') {
            throw "Unbekanntes oder geschütztes Feld '$key'."
        }
        $record[$key] = $Property[$key]
    }

    [pscustomobject] $record
}
