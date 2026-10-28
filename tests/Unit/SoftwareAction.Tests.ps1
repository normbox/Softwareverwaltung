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

        It 'führt den bestätigten Befehl aus, wenn er sich nicht geändert hat' {
            $planned = $msiRecord | Uninstall-Software -WhatIf
            $r = $msiRecord | Uninstall-Software -Confirm:$false -ConfirmedCommandLine $planned.CommandLine
            $r.Result | Should -Be 'Succeeded'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -Exactly
        }

        It 'führt nichts aus, wenn sich der Befehl seit der Bestätigung geändert hat, und protokolliert das' {
            $planned = $msiRecord | Uninstall-Software -WhatIf
            # Inzwischen ist ein winget-Paket bekannt: Auto wählt winget statt msiexec.
            $r = $wingetRecord | Uninstall-Software -Confirm:$false -ConfirmedCommandLine $planned.CommandLine
            $r.Result | Should -Be 'Cancelled'
            $r.Message.Code | Should -Be 'CommandChanged'
            $r.Message.Args[0] | Should -Match 'winget'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
            Test-Path "$Machine\$Guid" | Should -BeTrue
            (Get-ActionLog).Result | Should -Be 'Cancelled'
        }

        It 'prüft den bestätigten Befehl auch beim Aktualisieren' {
            $r = $wingetRecord | Update-Software -Confirm:$false -ConfirmedCommandLine 'C:\anderes.exe /S'
            $r.Result | Should -Be 'Cancelled'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
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
            $r.Message.Code | Should -Be 'WithNextMethod'
            $r.Message.Args[1] | Should -Be 'Msi'
            $r.Message.Text | Should -Match '-Method Msi'
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
            $problem = InModuleScope SoftwareInventory { New-InventoryMessage HelperWingetNotFound 'C:\x\winget.exe' }
            Set-HelperResult @{ Error = $problem; ExitCode = $null }
            $r = $wingetRecord | Uninstall-Software -Confirm:$false
            $r.Result | Should -Be 'Failed'
            # Mit nächster Methode eingepackt: WithNextMethod(<Prüffehler>, <Methode>)
            $r.Message.Code | Should -Be 'WithNextMethod'
            $r.Message.Args[0].Code | Should -Be 'HelperWingetNotFound'
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
            $r.Message.Code | Should -Be 'AppxRemoveFailed'
            $r.Message.Args[0] | Should -Match '0x80073CF6'
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
            $off = InModuleScope SoftwareInventory { New-InventoryMessage RestorePointProtectionDisabled }
            Set-HelperResult @{ ExitCode = 0; RestorePoint = 'NotAvailable'; RestorePointMessage = $off } { Remove-Item "$Machine\$Guid" }
            $r = $msiRecord | Uninstall-Software -CreateRestorePoint -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.RestorePoint | Should -Be 'NotAvailable'
            $r.RestorePointMessage.Code | Should -Be 'RestorePointProtectionDisabled'
        }

        It 'setzt die Aktion fort, wenn die UAC für den Punkt abgelehnt wird' {
            Mock -ModuleName SoftwareInventory Start-ElevatedHelper -ParameterFilter { -not $HelperPlan.FilePath } { @{ Status = 'ElevationDenied'; Error = 'Die Administratorabfrage (UAC) wurde abgelehnt.' } }
            Set-HelperResult @{ ExitCode = 0 } { Remove-Item "$User\UserApp" }
            $r = $userRecord | Uninstall-Software -CreateRestorePoint -Confirm:$false
            $r.RestorePoint | Should -Be 'Failed'
            $r.RestorePointMessage.Code | Should -Be 'RestorePointContinueWithout'
            $r.Result | Should -Be 'Succeeded'
        }

        It 'lässt sich pro Aufruf abschalten' {
            Set-InventorySetting -Enable RestorePoint | Out-Null
            ($msiRecord | Uninstall-Software -CreateRestorePoint:$false -Confirm:$false).RestorePoint | Should -Be 'NotRequested'
        }
    }

    Context 'Update-Warteschlange' {
        BeforeEach {
            # Zweites Programm im Benutzerbereich (läuft nie erhöht) und eines ohne winget (nicht ausführbar)
            New-UninstallKey $User 'UserTool' @{ DisplayName = 'User Tool'; DisplayVersion = '1.0' }
            $userWinget = InModuleScope SoftwareInventory -Parameters @{ K = "$User\UserTool" } {
                New-SoftwareRecord -Name 'User Tool' -Source Registry -Property @{ RegistryKey = $K; WingetId = 'User.Tool'; WingetSource = 'winget' }
            }
            $manualKey = '{99999999-2222-3333-4444-555555555555}'
            New-UninstallKey $Machine $manualKey @{ DisplayName = 'Manual Tool'; DisplayVersion = '3.0'; WindowsInstaller = 1 }
            $manual = InModuleScope SoftwareInventory -Parameters @{ K = "$Machine\$manualKey" } {
                New-SoftwareRecord -Name 'Manual Tool' -Source Registry -Property @{ RegistryKey = $K }
            }
            # Bewertung mit unbestätigter neuester Version (z. B. winget-Suche nach Name)
            $rating = [pscustomobject] @{
                PSTypeName = 'SoftwareInventory.SecurityRating'; Name = 'Contoso Tool'; Record = $wingetRecord; LatestVersion = '2.2.0'
                UpdateStatus = [pscustomobject] @{ Status = 'Outdated'; LatestVersion = '2.2.0'; Confirmed = $false }
            }
            $script:order = [System.Collections.Generic.List[string]]::new()
            # Einzelaufrufe (ohne Adminrechte): Version erhöhen
            Set-HelperResult @{ ExitCode = 0 } { Set-ItemProperty "$User\UserTool" -Name DisplayVersion -Value '1.1' }
            Mock -ModuleName SoftwareInventory Start-ElevatedHelper {
                $script:order.Add("single:$($HelperPlan.Arguments)")
                & $script:helperEffect
                @{ Status = 'Completed'; RestorePoint = $(if ($HelperPlan.RestorePoint) { 'Created' } else { 'NotRequested' }); ExitCode = 0; TimedOut = $false; Output = 'ok'; InstallerLog = $null; Error = $null }
            }
            # Stapel (erhöht): Schritte ausführen, solange BeforeStep zustimmt
            $script:batchStatus = 'Completed'
            Mock -ModuleName SoftwareInventory Start-ElevatedHelperBatch {
                $script:order.Add("batch:$($Steps.Count):rp=$RestorePoint")
                if ($script:batchStatus -ne 'Completed') { return @{ Status = $script:batchStatus; Error = [pscustomobject] @{ Code = 'ElevationDenied'; Args = @(); Text = 'abgelehnt' }; Done = 0 } }
                $done = 0
                for ($i = 0; $i -lt $Steps.Count; $i++) {
                    if (-not (& $BeforeStep $i)) { break }
                    Set-ItemProperty "TestRegistry:\Uninstall\Machine\{11111111-2222-3333-4444-555555555555}" -Name DisplayVersion -Value '2.2.0'
                    & $AfterStep $i @{ Status = 'Completed'; ExitCode = 0; TimedOut = $false; Output = 'ok'; InstallerLog = $null; Error = $null }
                    $done++
                }
                @{ Status = 'Completed'; Error = $null; RestorePoint = $(if ($RestorePoint) { 'Created' } else { 'NotRequested' }); RestorePointMessage = $null; Done = $done }
            }
        }

        It 'plant ohne Ausführung und Protokoll, mit Rechten, Befehl und Kennzeichnung unbestätigter Updates' {
            $plan = @($rating, $userWinget, $manual) | Get-UpdateQueuePlan
            $plan.Name | Should -Be @('Contoso Tool', 'User Tool', 'Manual Tool')
            $plan.Executable | Should -Be @($true, $true, $false)
            $plan.Elevated[0] | Should -BeTrue
            $plan.Elevated[1] | Should -BeFalse
            $plan[0].Unconfirmed | Should -BeTrue
            $plan[1].Unconfirmed | Should -BeFalse
            $plan[0].CommandLine | Should -Match 'upgrade --id Contoso\.Tool'
            $plan[2].Result | Should -Be 'ManualUpdateRequired'
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0
            Get-ActionLog | Should -BeNullOrEmpty
        }

        It 'führt erhöhte Einträge zuerst in einem Stapel aus, dann die übrigen, und meldet den Status je Eintrag' {
            $plan = @($userWinget, $rating) | Get-UpdateQueuePlan
            $control = [hashtable]::Synchronized(@{ State = 'Running' })
            $r = Invoke-UpdateQueue -Entry $plan -Control $control
            $script:order[0] | Should -Be 'batch:1:rp=False'
            $script:order[1] | Should -BeLike 'single:upgrade --id User.Tool*'
            $r.Name | Should -Be @('User Tool', 'Contoso Tool')
            $r.Result | Should -Be @('Succeeded', 'Succeeded')
            $control.Status[0] | Should -Be 'Succeeded'
            $control.Status[1] | Should -Be 'Succeeded'
            @(Get-ActionLog).Count | Should -Be 2
        }

        It 'legt einen einzigen Wiederherstellungspunkt vor der Warteschlange an' {
            $plan = @($rating, $userWinget) | Get-UpdateQueuePlan
            $r = Invoke-UpdateQueue -Entry $plan -CreateRestorePoint
            $script:order | Should -Contain 'batch:1:rp=True'
            @($script:order | Where-Object { $_ -like 'single:*' }).Count | Should -BeGreaterThan 0
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -ParameterFilter { $HelperPlan.RestorePoint } -Times 0
            @($r | Where-Object RestorePoint -EQ 'Created').Count | Should -Be 1
        }

        It 'nimmt den Wiederherstellungspunkt ohne erhöhte Einträge in einem eigenen kurzen Aufruf vorweg' {
            $r = Invoke-UpdateQueue -Entry (@($userWinget) | Get-UpdateQueuePlan) -CreateRestorePoint
            Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -ParameterFilter { $HelperPlan.RestorePoint -and -not $HelperPlan.FilePath } -Times 1
            $r.RestorePoint | Should -Be 'Created'
        }

        It 'bricht ab: führt nichts mehr aus und protokolliert den Rest als abgebrochen' {
            $plan = @($rating, $userWinget) | Get-UpdateQueuePlan
            $control = [hashtable]::Synchronized(@{ State = 'Cancelled' })
            $r = Invoke-UpdateQueue -Entry $plan -Control $control
            $r.Result | Should -Be @('Cancelled', 'Cancelled')
            $r[0].Message.Code | Should -Be 'QueueCancelled'
            @($script:order | Where-Object { $_ -like 'single:*' }).Count | Should -Be 0
            @(Get-ActionLog | Where-Object Result -EQ 'Cancelled').Count | Should -Be 2
        }

        It 'wartet, solange angehalten ist, und läuft danach weiter' {
            $script:control = [hashtable]::Synchronized(@{ State = 'Paused' })
            Mock -ModuleName SoftwareInventory Start-Sleep { $script:control['State'] = 'Running' }
            $r = Invoke-UpdateQueue -Entry (@($userWinget) | Get-UpdateQueuePlan) -Control $script:control
            $r.Result | Should -Be 'Succeeded'
            Should -Invoke -ModuleName SoftwareInventory Start-Sleep -Times 1
        }

        It 'überspringt nur den Eintrag, dessen Befehl sich seit der Bestätigung geändert hat' {
            $plan = @($rating, $userWinget) | Get-UpdateQueuePlan
            $plan[0].CommandLine = 'C:\anderes.exe /S'
            $r = Invoke-UpdateQueue -Entry $plan
            $r[0].Result | Should -Be 'Cancelled'
            $r[0].Message.Code | Should -Be 'CommandChanged'
            $r[1].Result | Should -Be 'Succeeded'
        }

        It 'lässt bei abgelehnter UAC-Abfrage die Einträge ohne Adminrechte trotzdem laufen' {
            $script:batchStatus = 'ElevationDenied'
            $r = Invoke-UpdateQueue -Entry (@($rating, $userWinget) | Get-UpdateQueuePlan)
            $r[0].Result | Should -Be 'ElevationDenied'
            $r[1].Result | Should -Be 'Succeeded'
        }
    }
}
