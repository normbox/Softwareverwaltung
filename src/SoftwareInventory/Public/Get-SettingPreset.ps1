function Get-SettingPreset {
    <#
    .SYNOPSIS
        Liefert die Werte einer Vorlage (Quick oder Thorough), ohne etwas zu speichern.
    .DESCRIPTION
        Für Oberflächen, die eine Vorlage nur vorbelegen und erst auf Wunsch speichern.
        Enable nennt die einzuschaltenden Quellen und Nutzungsspuren, FileScan die Werte für den
        Dateiscan. Externe Dienste, Ausschlüsse und Aktionen sind nie Teil einer Vorlage.
    .PARAMETER Preset
        Quick: alle Quellen, alle Nutzungsspuren, Dateiscan im Benutzerprofil ohne Temp und Hash.
        Thorough: wie Quick, aber Dateiscan aller festen Laufwerke einschließlich Temp, mit SHA256.
    .EXAMPLE
        Get-SettingPreset -Preset Quick
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SettingPreset')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Quick', 'Thorough')]
        [string] $Preset
    )

    $fileScan = if ($Preset -eq 'Quick') {
        [ordered]@{ Paths = [string[]] @('%USERPROFILE%'); Drives = [string[]] @(); IncludeTemp = $false; ComputeHash = $false }
    }
    else {
        [ordered]@{ Paths = [string[]] @(); Drives = [string[]] @(Get-ScanDrive | Where-Object IsDefault | ForEach-Object Drive); IncludeTemp = $true; ComputeHash = $true }
    }
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.SettingPreset'
        Preset     = $Preset
        Enable     = [string[]] @($script:InstalledSources + $script:TraceSources)
        FileScan   = [pscustomobject] $fileScan
    }
}
