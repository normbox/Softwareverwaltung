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
        [Parameter(Mandatory)] [ValidateSet('Registry', 'Winget', 'Appx')] [string] $Source,
        [hashtable] $Property = @{}
    )

    $record = [ordered]@{
        PSTypeName           = 'SoftwareInventory.SoftwareRecord'
        Name                 = $Name
        Publisher            = $null
        Version              = $null
        InstallType          = $null   # MSI, EXE, MSIX, Winget
        Scope                = $null   # Machine, User
        Architecture         = $null   # X64, X86, Arm64, Neutral
        Sources              = [string[]] @($Source)
        WingetId             = $null
        WingetSource         = $null
        AvailableVersion     = $null
        ProductCode          = $null
        RegistryKey          = $null
        PackageFullName      = $null
        PackageFamilyName    = $null
        InstallLocation      = $null
        InstallDate          = $null   # yyyy-MM-dd
        UninstallString      = $null
        QuietUninstallString = $null
    }

    foreach ($key in $Property.Keys) {
        if (-not $record.Contains($key) -or $key -in 'PSTypeName', 'Name', 'Sources') {
            throw "Unbekanntes oder geschütztes Feld '$key'."
        }
        $record[$key] = $Property[$key]
    }

    [pscustomobject] $record
}
