BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    $script:Machine = 'TestRegistry:\Uninstall\Machine'
    $script:User = 'TestRegistry:\Uninstall\User'
    $script:System = [Environment]::GetFolderPath('System')
    $script:Guid = '{11111111-2222-3333-4444-555555555555}'

    function New-UninstallKey {
        param([string] $Root, [string] $Name, [hashtable] $Values)
        $key = New-Item -Path $Root -Name $Name -Force
        foreach ($v in $Values.GetEnumerator()) {
            $type = if ($v.Value -is [int]) { 'DWord' } else { 'String' }
            New-ItemProperty -Path $key.PSPath -Name $v.Key -Value $v.Value -PropertyType $type | Out-Null
        }
    }

    function New-TestRecord {
        param([hashtable] $Property)
        InModuleScope SoftwareInventory -Parameters @{ P = $Property } { New-SoftwareRecord -Name 'Contoso Tool' -Source Registry -Property $P }
    }

    # Simuliert den Helfer: Ergebnis vorgeben und optional den Zustand ändern (Schlüssel löschen, Version setzen).
    function Set-HelperResult {
        param([hashtable] $Result, [scriptblock] $Effect = {})
        $script:helperResult = $Result
        $script:helperEffect = $Effect
    }
}

Describe 'Update-Software und Uninstall-Software' {
    BeforeEach {
        New-Item -Path $Machine, $User -Force | Out-Null
        $appData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $settingsFile = Join-Path $appData 'settings.json'
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $appData }
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(
                @{ Path = 'TestRegistry:\Uninstall\Machine'; Scope = 'Machine'; Architecture = 'X64' }
                @{ Path = 'TestRegistry:\Uninstall\User'; Scope = 'User'; Architecture = $null }
            )
        }
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1_x64__8wekyb3d8bbwe\winget.exe' }
        Mock -ModuleName SoftwareInventory Get-WingetInstalledVersion { $null }
        Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { $null }
        Mock -ModuleName SoftwareInventory Test-UserWritablePath { $false }
        Mock -ModuleName SoftwareInventory Invoke-AppxRemoval { }
        Mock -ModuleName SoftwareInventory Start-ElevatedHelper {
            & $script:helperEffect
            $r = @{ Status = 'Completed'; RestorePoint = 'NotRequested'; ExitCode = 0; TimedOut = $false; Output = 'ok'; InstallerLog = $null; Error = $null }
            foreach ($k in $script:helperResult.Keys) { $r[$k] = $script:helperResult[$k] }
            if ($HelperPlan.RestorePoint -and $r.RestorePoint -eq 'NotRequested') { $r.RestorePoint = 'Created'; $r.RestorePointMessage = 'angelegt' }
            $r
        }
        InModuleScope SoftwareInventory { $script:VerifyTimeoutSeconds = 0; $script:VerifyIntervalSeconds = 0 }

        New-UninstallKey $Machine $Guid @{ DisplayName = 'Contoso Tool'; DisplayVersion = '2.1.0'; WindowsInstaller = 1 }
        New-UninstallKey $User 'UserApp' @{ DisplayName = 'User App'; DisplayVersion = '0.9'; UninstallString = "`"$System\msiexec.exe`" /S" }
        $msiRecord = New-TestRecord @{ RegistryKey = "$Machine\$Guid" }
        $wingetRecord = New-TestRecord @{ RegistryKey = "$Machine\$Guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }
        $userRecord = New-TestRecord @{ RegistryKey = "$User\UserApp" }
        Set-HelperResult @{ ExitCode = 0 } { Remove-Item "$Machine\$Guid" }
    }

    AfterAll {
        InModuleScope SoftwareInventory { $script:VerifyTimeoutSeconds = 60; $script:VerifyIntervalSeconds = 2 }
    }

    Context '-WhatIf' {
        It 'führt nichts aus, liefert Planned mit genauem Befehl und protokolliert nicht' {
            $r = $msiRecord | Uninstall-Software -WhatIf
            $r.PSObject.TypeNames | Should -Contain 'SoftwareInventory.ActionResult'
            $r.Result | Should -Be 'Planned'
            $r.CommandLine | Should -Be "$System\msiexec.exe /x $Guid /qn /norestart /l*v <Installer-Log>"
            $r.Elevated | Should -BeTrue
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
            Get-ActionLog | Should -BeNullOrEmpty
            Test-Path "$Machine\$Guid" | Should -BeTrue
        }

        It 'entfernt auch keine Store-App' {
            Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { [pscustomobject] @{ PackageFullName = 'C.App_1_x64__a'; Version = '1.0' } }
            $r = New-TestRecord @{ PackageFamilyName = 'C.App_a' } | Uninstall-Software -WhatIf
            $r.Result | Should -Be 'Planned'
            Should -Invoke -ModuleName SoftwareInventory Invoke-AppxRemoval -Times 0
        }
    }

    Context 'Deinstallieren' {
        It 'meldet Succeeded nur, wenn der Eintrag danach weg ist, und protokolliert Start und Abschluss' {
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.PresentBefore | Should -BeTrue
            $r.PresentAfter | Should -BeFalse
            $r.VersionBefore | Should -Be '2.1.0'
            $r.ExitCode | Should -Be 0
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter {
                -not $NoElevation -and $HelperPlan.MsiLog -and $HelperPlan.Arguments -eq "/x $Guid /qn /norestart"
            }
            $log = Get-ActionLog
            $log.Result | Should -Be 'Succeeded'
            $log.Method | Should -Be 'Msi'
            $log.Elevated | Should -BeTrue
            $log.CommandLine | Should -Not -BeNullOrEmpty
            $log.User | Should -Not -BeNullOrEmpty
            $log.CompletedAt | Should -Not -BeNullOrEmpty
        }

        It 'meldet NotVerified, wenn Exit-Code 0 kommt, das Programm aber noch da ist, und nennt die nächste Methode' {
            Set-HelperResult @{ ExitCode = 0 }
            $r = $wingetRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'NotVerified'
            $r.PresentAfter | Should -BeTrue
            $r.NextMethod | Should -Be 'Msi'
            $r.Message | Should -Match '-Method Msi'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1
        }

        It 'versucht nach einem Fehler keine andere Methode automatisch' {
            Set-HelperResult @{ ExitCode = 1603 }
            $r = $wingetRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Method | Should -Be 'Winget'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1
        }

        It 'bildet <Code> auf <Result> ab' -ForEach @(
            @{ Code = 3010; Result = 'SucceededRebootRequired' }
            @{ Code = 1641; Result = 'SucceededRebootRequired' }
            @{ Code = 1602; Result = 'Cancelled' }
            @{ Code = 1605; Result = 'NotInstalled' }
            @{ Code = -1978334975; Result = 'Failed' }
        ) {
            Set-HelperResult @{ ExitCode = $Code }
            ($msiRecord | Uninstall-Software -Confirm:$false).Result | Should -Be $Result
        }

        It 'meldet ElevationDenied, wenn die UAC-Abfrage abgelehnt wird' {
            Set-HelperResult @{ Status = 'ElevationDenied'; Error = 'Die Administratorabfrage (UAC) wurde abgelehnt.'; ExitCode = $null }
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'ElevationDenied'
            $r.PresentAfter | Should -BeTrue
            (Get-ActionLog).Result | Should -Be 'ElevationDenied'
        }

        It 'meldet Timeout, ohne Erfolg zu behaupten' {
            Set-HelperResult @{ TimedOut = $true; ExitCode = $null }
            ($msiRecord | Uninstall-Software -Confirm:$false).Result | Should -Be 'Timeout'
        }

        It 'meldet Prüffehler des Helfers als Failed' {
            Set-HelperResult @{ Error = 'winget wurde im Administratorkontext nicht gefunden'; ExitCode = $null }
            $r = $wingetRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Message | Should -Match 'Administratorkontext'
        }

        It 'führt HKCU-Einträge ohne Adminrechte aus' {
            Set-HelperResult @{ ExitCode = 0 } { Remove-Item "$User\UserApp" }
            $r = $userRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.Elevated | Should -BeFalse
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { $NoElevation -and -not $HelperPlan.Elevate }
        }

        It 'entfernt Store-Apps im Benutzerkontext ohne Helfer' {
            $script:appx = [pscustomobject] @{ PackageFullName = 'C.App_1_x64__a'; Version = '1.0' }
            Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { $script:appx }
            Mock -ModuleName SoftwareInventory Invoke-AppxRemoval { $script:appx = $null }
            $r = New-TestRecord @{ PackageFamilyName = 'C.App_a' } | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.Method | Should -Be 'Appx'
            Should -Invoke -ModuleName SoftwareInventory Invoke-AppxRemoval -Times 1 -ParameterFilter { $PackageFullName -eq 'C.App_1_x64__a' }
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
        }

        It 'meldet Fehler beim Entfernen einer Store-App' {
            Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { [pscustomobject] @{ PackageFullName = 'C.App_1_x64__a'; Version = '1.0' } }
            Mock -ModuleName SoftwareInventory Invoke-AppxRemoval { throw 'Bereitstellung fehlgeschlagen (0x80073CF6)' }
            $r = New-TestRecord @{ PackageFamilyName = 'C.App_a' } | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Message | Should -Match '0x80073CF6'
        }

        It 'akzeptiert Objekte mit .Record (z. B. aus Get-SecurityRating)' {
            $r = [pscustomobject] @{ Name = 'Contoso Tool'; Rating = 'Red'; Record = $msiRecord } | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
        }

        It 'meldet NotInstalled ohne Ausführung, protokolliert aber' {
            Remove-Item "$Machine\$Guid"
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'NotInstalled'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
            (Get-ActionLog).Result | Should -Be 'NotInstalled'
        }

        It 'verlangt für Deinstallation eine Bestätigung (ConfirmImpact High)' {
            $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command Uninstall-Software))
            $meta.ConfirmImpact | Should -Be 'High'
            $meta.SupportsShouldProcess | Should -BeTrue
            [System.Management.Automation.CommandMetadata]::new((Get-Command Update-Software)).ConfirmImpact | Should -Be 'Medium'
        }
    }

    Context 'Installer-Logs' {
        It 'hebt das MSI-Log bei Fehlern komprimiert auf' {
            Set-HelperResult @{ ExitCode = 1603; InstallerLog = 'MSI (s) Fehler 1603' }
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.InstallerLog | Should -BeLike '*.zip'
            Test-Path $r.InstallerLog | Should -BeTrue
            Get-ChildItem (Join-Path $appData 'logs\installer') -Filter '*.log' | Should -BeNullOrEmpty
        }

        It 'speichert das MSI-Log nach Erfolg gar nicht' {
            Set-HelperResult @{ ExitCode = 0; InstallerLog = 'MSI (s) ok' } { Remove-Item "$Machine\$Guid" }
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.InstallerLog | Should -BeNullOrEmpty
            Test-Path (Join-Path $appData 'logs\installer') | Should -BeFalse
        }
    }

    Context 'Aktualisieren' {
        It 'meldet Succeeded nur bei höherer Version' {
            Set-HelperResult @{ ExitCode = 0 } { Set-ItemProperty "$Machine\$Guid" -Name DisplayVersion -Value '2.2.0' }
            $r = $wingetRecord | Update-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.VersionBefore | Should -Be '2.1.0'
            $r.VersionAfter | Should -Be '2.2.0'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { $HelperPlan.Arguments -like 'upgrade --id Contoso.Tool --exact --source winget*' }
        }

        It 'erkennt ein MSI-Update mit neuem ProductCode über winget' {
            $script:wingetVersion = '2.1.0'
            Mock -ModuleName SoftwareInventory Get-WingetInstalledVersion -ParameterFilter { $Id -eq 'Contoso.Tool' -and $Source -eq 'winget' } { $script:wingetVersion }
            Set-HelperResult @{ ExitCode = 0 } { Remove-Item "$Machine\$Guid"; $script:wingetVersion = '2.2.0' }
            $r = $wingetRecord | Update-Software -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.VersionAfter | Should -Be '2.2.0'
            $r.PresentAfter | Should -BeTrue
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { $HelperPlan.Elevate }
        }

        It 'meldet NotVerified, wenn die Version gleich bleibt' {
            Set-HelperResult @{ ExitCode = 0 }
            ($wingetRecord | Update-Software -Confirm:$false).Result | Should -Be 'NotVerified'
        }

        It 'meldet NoUpdateAvailable bei winget UPDATE_NOT_APPLICABLE' {
            Set-HelperResult @{ ExitCode = -1978335189 }
            $r = $wingetRecord | Update-Software -Confirm:$false
            $r.Result | Should -Be 'NoUpdateAvailable'
            $r.ExitCodeHex | Should -Be '0x8A15002B'
        }

        It 'lädt ohne winget nichts herunter, sondern liefert den Herstellerlink' {
            Set-ItemProperty "$Machine\$Guid" -Name URLUpdateInfo -Value 'https://contoso.example/update'
            $r = $msiRecord | Update-Software -Confirm:$false
            $r.Result | Should -Be 'ManualUpdateRequired'
            $r.VendorUrl | Should -Be 'https://contoso.example/update'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
            (Get-ActionLog).Result | Should -Be 'ManualUpdateRequired'
        }
    }

    Context 'Wiederherstellungspunkt' {
        It 'legt standardmäßig keinen an' {
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.RestorePoint | Should -Be 'NotRequested'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { -not $HelperPlan.RestorePoint }
        }

        It 'legt ihn bei erhöhten Aktionen im selben Helfer vor der Aktion an, wenn die Einstellung an ist' {
            Set-InventorySetting -Enable RestorePoint | Out-Null
            $r = $msiRecord | Uninstall-Software -Confirm:$false
            $r.RestorePoint | Should -Be 'Created'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { $HelperPlan.RestorePoint -and $HelperPlan.RestorePointType -eq 1 -and $HelperPlan.FilePath }
            (Get-ActionLog).RestorePoint | Should -Be 'Created'
        }

        It 'nutzt bei Aktionen ohne Adminrechte einen eigenen erhöhten Aufruf nur für den Punkt' {
            Set-HelperResult @{ ExitCode = 0 } { if ($HelperPlan.FilePath) { Remove-Item "$User\UserApp" } }
            $r = $userRecord | Uninstall-Software -CreateRestorePoint -Confirm:$false
            $r.RestorePoint | Should -Be 'Created'
            $r.Result | Should -Be 'Succeeded'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { -not $NoElevation -and $HelperPlan.RestorePoint -and -not $HelperPlan.FilePath }
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -ParameterFilter { $NoElevation -and -not $HelperPlan.RestorePoint -and $HelperPlan.FilePath }
        }

        It 'setzt die Aktion fort, wenn der Punkt nicht verfügbar ist, und meldet den Grund' {
            Set-HelperResult @{ ExitCode = 0; RestorePoint = 'NotAvailable'; RestorePointMessage = 'Computerschutz ist ausgeschaltet' } { Remove-Item "$Machine\$Guid" }
            $r = $msiRecord | Uninstall-Software -CreateRestorePoint -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.RestorePoint | Should -Be 'NotAvailable'
            $r.RestorePointMessage | Should -Be 'Computerschutz ist ausgeschaltet'
        }

        It 'setzt die Aktion fort, wenn die UAC für den Punkt abgelehnt wird' {
            Mock -ModuleName SoftwareInventory Start-ElevatedHelper -ParameterFilter { -not $HelperPlan.FilePath } { @{ Status = 'ElevationDenied'; Error = 'Die Administratorabfrage (UAC) wurde abgelehnt.' } }
            Set-HelperResult @{ ExitCode = 0 } { Remove-Item "$User\UserApp" }
            $r = $userRecord | Uninstall-Software -CreateRestorePoint -Confirm:$false
            $r.RestorePoint | Should -Be 'Failed'
            $r.RestorePointMessage | Should -Match 'ohne Wiederherstellungspunkt fortgesetzt'
            $r.Result | Should -Be 'Succeeded'
        }

        It 'lässt sich pro Aufruf abschalten' {
            Set-InventorySetting -Enable RestorePoint | Out-Null
            ($msiRecord | Uninstall-Software -CreateRestorePoint:$false -Confirm:$false).RestorePoint | Should -Be 'NotRequested'
        }
    }
}
