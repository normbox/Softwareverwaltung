function Set-InventorySetting {
    <#
    .SYNOPSIS
        Schaltet Quellen, Nutzungsspuren und Scan-Bereiche einzeln ein oder aus.
    .DESCRIPTION
        Standardmäßig ist alles aus. Eine Vorlage (-Preset) belegt die Schalter nur vor;
        danach lassen sie sich einzeln ändern. Usage (Privat/Firma) ist reine Information
        und schaltet nichts frei oder ab.
    .PARAMETER Preset
        Quick: alle Quellen, alle Nutzungsspuren, Dateiscan im Benutzerprofil ohne Temp und Hash.
        Thorough: wie Quick, aber Dateiscan aller festen Laufwerke einschließlich Temp, mit SHA256.
        Wird vor den übrigen Parametern angewendet.
    .PARAMETER Enable
        Einzuschaltende Bereiche: RegistryMachine, RegistryUser, Winget, Appx,
        UserAssist, Process, Autostart, ScheduledTask.
    .PARAMETER Disable
        Auszuschaltende Bereiche (gleiche Namen wie -Enable).
    .PARAMETER ScanPath
        Ordner für den Dateiscan (ersetzt die bisherige Liste). Umgebungsvariablen wie %USERPROFILE% erlaubt.
    .PARAMETER ScanDrive
        Laufwerke für den Dateiscan (ersetzt die bisherige Liste), z. B. C, D.
    .PARAMETER Reset
        Setzt alles auf „aus“ zurück (Usage bleibt erhalten).
    .EXAMPLE
        Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx
    .EXAMPLE
        Set-InventorySetting -Preset Quick -Disable ScheduledTask
    .EXAMPLE
        Set-InventorySetting -ScanDrive C, D -IncludeTemp $true -ComputeHash $true
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SoftwareInventory.Setting')]
    param(
        [ValidateSet('Quick', 'Thorough')]
        [string] $Preset,

        [ValidateSet('RegistryMachine', 'RegistryUser', 'Winget', 'Appx', 'UserAssist', 'Process', 'Autostart', 'ScheduledTask')]
        [string[]] $Enable = @(),

        [ValidateSet('RegistryMachine', 'RegistryUser', 'Winget', 'Appx', 'UserAssist', 'Process', 'Autostart', 'ScheduledTask')]
        [string[]] $Disable = @(),

        [AllowEmptyCollection()]
        [string[]] $ScanPath,

        [AllowEmptyCollection()]
        [string[]] $ScanDrive,

        [bool] $IncludeTemp,

        [bool] $ComputeHash,

        [ValidateSet('Private', 'Company')]
        [string] $Usage,

        [switch] $Reset
    )

    $setting = Read-InventorySetting
    if ($Reset) {
        $usageBefore = $setting.Usage
        $setting = New-DefaultSetting
        $setting.Usage = $usageBefore
    }

    if ($Preset) {
        foreach ($s in $script:InstalledSources) { $setting.Sources.$s = $true }
        foreach ($t in $script:TraceSources) { $setting.Traces.$t = $true }
        if ($Preset -eq 'Quick') {
            $setting.FileScan.Paths = [string[]] @('%USERPROFILE%')
            $setting.FileScan.Drives = [string[]] @()
            $setting.FileScan.IncludeTemp = $false
            $setting.FileScan.ComputeHash = $false
        }
        else {
            $setting.FileScan.Paths = [string[]] @()
            $setting.FileScan.Drives = [string[]] @(Get-ScanDrive | Where-Object IsDefault | ForEach-Object Drive)
            $setting.FileScan.IncludeTemp = $true
            $setting.FileScan.ComputeHash = $true
        }
    }

    foreach ($name in $Enable) { Set-SettingSwitch -Setting $setting -Name $name -Value $true }
    foreach ($name in $Disable) { Set-SettingSwitch -Setting $setting -Name $name -Value $false }

    if ($PSBoundParameters.ContainsKey('ScanPath')) { $setting.FileScan.Paths = [string[]] @($ScanPath | Where-Object { $_ }) }
    if ($PSBoundParameters.ContainsKey('ScanDrive')) {
        $setting.FileScan.Drives = [string[]] @($ScanDrive | Where-Object { $_ } | ForEach-Object { (ConvertTo-DriveRoot $_).TrimEnd('\') })
    }
    if ($PSBoundParameters.ContainsKey('IncludeTemp')) { $setting.FileScan.IncludeTemp = $IncludeTemp }
    if ($PSBoundParameters.ContainsKey('ComputeHash')) { $setting.FileScan.ComputeHash = $ComputeHash }
    if ($PSBoundParameters.ContainsKey('Usage')) { $setting.Usage = $Usage }

    if ($PSCmdlet.ShouldProcess((Get-SettingsPath), 'Einstellungen speichern')) {
        Write-InventorySetting -Setting $setting
    }
    $setting
}

function Set-SettingSwitch {
    param($Setting, [string] $Name, [bool] $Value)
    $group = if ($Name -in $script:InstalledSources) { 'Sources' } else { 'Traces' }
    $Setting.$group.$Name = $Value
}
