function Get-SettingPreset {
    <#
    .SYNOPSIS
        Liefert die Werte einer Vorlage (Quick oder Thorough), ohne etwas zu speichern.
    .DESCRIPTION
        Für Oberflächen, die eine Vorlage nur vorbelegen und erst auf Wunsch speichern.
        Enable nennt die einzuschaltenden Quellen und Nutzungsspuren. FileScan nennt die Option
        „Wo suchen“ (Mode) und nur die Liste dieser Option (Paths bei Folders, Drives bei Drives);
        die Liste der anderen Option bleibt beim Anwenden unberührt. Externe Dienste, Ausschlüsse,
        Aktionen und der Hauptschalter PortableSearch sind nie Teil einer Vorlage.
    .PARAMETER Preset
        Quick: alle Quellen und Nutzungsspuren, nur bestimmte Ordner (Benutzerprofil), ohne Temp und Hash.
        Thorough: wie Quick, aber ganze Laufwerke (alle festen), mit Temp und SHA256.
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
        [ordered]@{ Mode = 'Folders'; Paths = [string[]] @('%USERPROFILE%'); IncludeTemp = $false; ComputeHash = $false }
    }
    else {
        [ordered]@{ Mode = 'Drives'; Drives = [string[]] @(Get-ScanDrive | Where-Object IsDefault | ForEach-Object Drive); IncludeTemp = $true; ComputeHash = $true }
    }
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.SettingPreset'
        Preset     = $Preset
        Enable     = [string[]] @($script:InstalledSources + $script:TraceSources)
        FileScan   = [pscustomobject] $fileScan
    }
}
