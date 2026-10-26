function Set-InventorySetting {
    <#
    .SYNOPSIS
        Schaltet Quellen, Nutzungsspuren und Scan-Bereiche einzeln ein oder aus.
    .DESCRIPTION
        Standardmäßig ist alles aus. Eine Vorlage (-Preset) belegt die Schalter nur vor;
        danach lassen sie sich einzeln ändern. Usage (Privat/Firma) ist reine Information
        und schaltet nichts frei oder ab.
    .PARAMETER Preset
        Quick: alle Quellen, alle Nutzungsspuren, „Nur bestimmte Ordner“ mit dem Benutzerprofil, ohne Temp und Hash.
        Thorough: wie Quick, aber „Ganze Laufwerke“ mit allen festen Laufwerken, einschließlich Temp, mit SHA256.
        Eine Vorlage setzt die Option und nur deren Liste; die Liste der anderen Option bleibt.
        Wird vor den übrigen Parametern angewendet. Externe Dienste und den Hauptschalter
        PortableSearch schaltet keine Vorlage ein.
    .PARAMETER Enable
        Einzuschaltende Bereiche: RegistryMachine, RegistryUser, Winget, Appx,
        UserAssist, Process, Autostart, ScheduledTask sowie die externen Dienste
        WingetSearch, GitHub, NVD, KEV, EPSS. Externe Dienste schaltet keine Vorlage ein.
        RestorePoint: vor jedem Aktualisieren/Deinstallieren einen Wiederherstellungspunkt
        anlegen (eigene UAC-Abfrage). Keine Vorlage schaltet ihn ein.
    .PARAMETER Disable
        Auszuschaltende Bereiche (gleiche Namen wie -Enable).
    .PARAMETER ScanMode
        „Wo suchen“: Drives (ganze Laufwerke), Folders (nur bestimmte Ordner) oder None. Durchsucht wird
        nur die Liste dieser Option; die andere bleibt gespeichert, wird aber nicht genutzt.
    .PARAMETER ScanPath
        Ordner für „Nur bestimmte Ordner“ (ersetzt die bisherige Liste). Umgebungsvariablen wie %USERPROFILE% erlaubt.
    .PARAMETER ScanDrive
        Laufwerke für „Ganze Laufwerke“ (ersetzt die bisherige Liste), z. B. C, D.
    .PARAMETER ExcludePath
        Eigene Ordner, die nie betreten werden – weder vom Dateiscan noch bei Spuren (ersetzt die
        bisherige Liste). Umgebungsvariablen erlaubt. Vorlagen ändern diese Liste nicht.
    .PARAMETER SmartExclusions
        $false schaltet die Herstellerordner-Regel und den Abgleich über Name/Version ab
        (mehr Treffer). Feste Systemausschlüsse und Ordner installierter Programme bleiben.
        Standard: $true. Vorlagen ändern den Wert nicht.
    .PARAMETER LogRetentionDays
        Logs und Zwischenspeicher, die älter sind, werden beim Laden des Moduls gelöscht. Standard: 30.
    .PARAMETER LogMaxSizeMB
        Obergrenze für Logs und Zwischenspeicher zusammen; darüber wird das Älteste zuerst gelöscht. Standard: 100.
    .PARAMETER PortableSearch
        Hauptschalter für die Suche nach portablen Programmen im vollständigen Scan (Invoke-InventoryScan).
        Standard: aus. Aus = keine Suche; Nutzungsspuren, Ordner und Laufwerke bleiben gespeichert.
        Keine Vorlage schaltet ihn ein. Get-PortableSoftware selbst ist davon nicht betroffen.
    .PARAMETER AdvisorEnabled
        KI-Berater ein- oder ausschalten. Standard: aus. Keine Vorlage schaltet ihn ein.
    .PARAMETER AdvisorPreset
        Lokaler Server: Ollama, LMStudio, Unsloth oder Custom (siehe Get-AdvisorEndpointPreset).
        Belegt die Adresse mit der Standardadresse vor, außer -AdvisorEndpoint ist angegeben.
    .PARAMETER AdvisorEndpoint
        Basisadresse der OpenAI-kompatiblen Schnittstelle, z. B. http://localhost:11434/v1. Leer löscht sie.
    .PARAMETER AdvisorModel
        Modellname, wie ihn der Server unter /v1/models nennt. Es gibt keinen Standard. Leer löscht ihn.
    .PARAMETER Reset
        Setzt alles auf den Ausgangszustand zurück: aus, keine eigenen Ausschlüsse,
        SmartExclusions an (Usage bleibt erhalten).
    .EXAMPLE
        Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx
    .EXAMPLE
        Set-InventorySetting -Preset Quick -Disable ScheduledTask
    .EXAMPLE
        Set-InventorySetting -PortableSearch $true -ScanMode Drives -ScanDrive C, D -IncludeTemp $true -ComputeHash $true
    .EXAMPLE
        Set-InventorySetting -PortableSearch $true -ScanMode Folders -ScanPath '%USERPROFILE%', 'D:\Tools'
    .EXAMPLE
        Set-InventorySetting -ExcludePath '%USERPROFILE%\Projekte\Builds' -SmartExclusions $false
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SoftwareInventory.Setting')]
    param(
        [ValidateSet('Quick', 'Thorough')]
        [string] $Preset,

        [ValidateSet('RegistryMachine', 'RegistryUser', 'Winget', 'Appx', 'UserAssist', 'Process', 'Autostart', 'ScheduledTask',
            'WingetSearch', 'GitHub', 'NVD', 'KEV', 'EPSS', 'RestorePoint')]
        [string[]] $Enable = @(),

        [ValidateSet('RegistryMachine', 'RegistryUser', 'Winget', 'Appx', 'UserAssist', 'Process', 'Autostart', 'ScheduledTask',
            'WingetSearch', 'GitHub', 'NVD', 'KEV', 'EPSS', 'RestorePoint')]
        [string[]] $Disable = @(),

        [ValidateSet('None', 'Drives', 'Folders')]
        [string] $ScanMode,

        [AllowEmptyCollection()]
        [string[]] $ScanPath,

        [AllowEmptyCollection()]
        [string[]] $ScanDrive,

        [bool] $IncludeTemp,

        [bool] $ComputeHash,

        [AllowEmptyCollection()]
        [string[]] $ExcludePath,

        [bool] $SmartExclusions,

        [ValidateRange(1, 3650)]
        [int] $LogRetentionDays,

        [ValidateRange(1, 102400)]
        [int] $LogMaxSizeMB,

        [ValidateSet('Private', 'Company')]
        [string] $Usage,

        [bool] $AdvisorEnabled,

        [bool] $PortableSearch,

        [ValidateSet('Ollama', 'LMStudio', 'Unsloth', 'Custom')]
        [string] $AdvisorPreset,

        [AllowEmptyString()]
        [string] $AdvisorEndpoint,

        [AllowEmptyString()]
        [string] $AdvisorModel,

        [switch] $Reset
    )

    $setting = Read-InventorySetting
    if ($Reset) {
        $usageBefore = $setting.Usage
        $setting = New-DefaultSetting
        $setting.Usage = $usageBefore
    }

    if ($Preset) {
        $values = Get-SettingPreset -Preset $Preset
        foreach ($name in $values.Enable) { Set-SettingSwitch -Setting $setting -Name $name -Value $true }
        # Option „Wo suchen“ und nur deren Liste; die Liste der anderen Option bleibt unberührt.
        $setting.FileScan.Mode = $values.FileScan.Mode
        $list = if ($values.FileScan.Mode -eq 'Folders') { 'Paths' } else { 'Drives' }
        $setting.FileScan.$list = $values.FileScan.$list
        foreach ($name in 'IncludeTemp', 'ComputeHash') { $setting.FileScan.$name = $values.FileScan.$name }
    }

    foreach ($name in $Enable) { Set-SettingSwitch -Setting $setting -Name $name -Value $true }
    foreach ($name in $Disable) { Set-SettingSwitch -Setting $setting -Name $name -Value $false }

    if ($PSBoundParameters.ContainsKey('ScanMode')) { $setting.FileScan.Mode = if ($ScanMode -eq 'None') { $null } else { $ScanMode } }
    if ($PSBoundParameters.ContainsKey('ScanPath')) { $setting.FileScan.Paths = [string[]] @($ScanPath | Where-Object { $_ }) }
    if ($PSBoundParameters.ContainsKey('ScanDrive')) {
        $setting.FileScan.Drives = [string[]] @($ScanDrive | Where-Object { $_ } | ForEach-Object { (ConvertTo-DriveRoot $_).TrimEnd('\') })
    }
    if ($PSBoundParameters.ContainsKey('IncludeTemp')) { $setting.FileScan.IncludeTemp = $IncludeTemp }
    if ($PSBoundParameters.ContainsKey('ComputeHash')) { $setting.FileScan.ComputeHash = $ComputeHash }
    if ($PSBoundParameters.ContainsKey('ExcludePath')) { $setting.FileScan.ExcludePaths = [string[]] @($ExcludePath | Where-Object { $_ }) }
    if ($PSBoundParameters.ContainsKey('SmartExclusions')) { $setting.FileScan.SmartExclusions = $SmartExclusions }
    if ($PSBoundParameters.ContainsKey('LogRetentionDays')) { $setting.Maintenance.LogRetentionDays = $LogRetentionDays }
    if ($PSBoundParameters.ContainsKey('LogMaxSizeMB')) { $setting.Maintenance.LogMaxSizeMB = $LogMaxSizeMB }
    if ($PSBoundParameters.ContainsKey('Usage')) { $setting.Usage = $Usage }
    if ($PSBoundParameters.ContainsKey('AdvisorEnabled')) { $setting.Advisor.Enabled = $AdvisorEnabled }
    if ($PSBoundParameters.ContainsKey('PortableSearch')) { $setting.PortableSearch.Enabled = $PortableSearch }
    if ($PSBoundParameters.ContainsKey('AdvisorPreset')) {
        $setting.Advisor.Preset = $AdvisorPreset
        # Vorgabe belegt die Adresse vor; eine ausdrücklich angegebene Adresse gewinnt.
        $presetEndpoint = $script:AdvisorPresets[$AdvisorPreset].Endpoint
        if ($presetEndpoint -and -not $PSBoundParameters.ContainsKey('AdvisorEndpoint')) { $setting.Advisor.Endpoint = $presetEndpoint }
    }
    if ($PSBoundParameters.ContainsKey('AdvisorEndpoint')) {
        if ($AdvisorEndpoint -and -not (Test-AdvisorEndpoint $AdvisorEndpoint)) {
            $exception = [System.ArgumentException]::new((Get-LocalizedString 'SettingsErrorInvalidAdvisorEndpoint' @($AdvisorEndpoint)), 'AdvisorEndpoint')
            $exception.Data['Code'] = 'InvalidAdvisorEndpoint'
            throw $exception
        }
        $setting.Advisor.Endpoint = if ($AdvisorEndpoint) { $AdvisorEndpoint.TrimEnd('/') } else { $null }
    }
    if ($PSBoundParameters.ContainsKey('AdvisorModel')) { $setting.Advisor.Model = if ($AdvisorModel) { $AdvisorModel } else { $null } }

    if ($PSCmdlet.ShouldProcess((Get-SettingsPath), 'Einstellungen speichern')) {
        Write-InventorySetting -Setting $setting
    }
    $setting
}

function Set-SettingSwitch {
    param($Setting, [string] $Name, [bool] $Value)
    $group = if ($Name -in $script:InstalledSources) { 'Sources' }
    elseif ($Name -in $script:ServiceSources) { 'Services' }
    elseif ($Name -in $script:ActionOptions) { 'Actions' }
    else { 'Traces' }
    $Setting.$group.$Name = $Value
}
