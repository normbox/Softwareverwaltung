BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    $script:Machine = 'TestRegistry:\Uninstall\Machine'
    $script:User = 'TestRegistry:\Uninstall\User'
    $script:System = [Environment]::GetFolderPath('System')

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
        InModuleScope SoftwareInventory -Parameters @{ P = $Property } {
            $name = if ($P['Name']) { $P['Name'] } else { 'Contoso Tool' }
            $props = @{}
            foreach ($k in $P.Keys) { if ($k -ne 'Name') { $props[$k] = $P[$k] } }
            New-SoftwareRecord -Name $name -Source Registry -Property $props
        }
    }

    function Get-Plan {
        param($Record, [string] $Action = 'Uninstall', [string] $Method = 'Auto')
        InModuleScope SoftwareInventory -Parameters @{ R = $Record; A = $Action; M = $Method } {
            New-ActionPlan -Action $A -Record $R -Method $M
        }
    }
}

Describe 'New-ActionPlan' {
    BeforeEach {
        New-Item -Path $Machine, $User -Force | Out-Null
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(
                @{ Path = 'TestRegistry:\Uninstall\Machine'; Scope = 'Machine'; Architecture = 'X64' }
                @{ Path = 'TestRegistry:\Uninstall\User'; Scope = 'User'; Architecture = $null }
            )
        }
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1_x64__8wekyb3d8bbwe\winget.exe' }
        Mock -ModuleName SoftwareInventory Get-WingetInstalledVersion { $null }
        # Lesende winget-Prüfung der ID: Katalog-ID gefunden (Standardfall)
        Mock -ModuleName SoftwareInventory Invoke-WingetCli { @{ ExitCode = 0; Lines = @() } }
        Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { $null }
        Mock -ModuleName SoftwareInventory Test-UserWritablePath { $false }

        $guid = '{11111111-2222-3333-4444-555555555555}'
        New-UninstallKey $Machine $guid @{
            DisplayName = 'Contoso Tool'; DisplayVersion = '2.1.0'; WindowsInstaller = 1
            UninstallString = "MsiExec.exe /X$guid"; QuietUninstallString = "MsiExec.exe /X$guid /qn"
        }
        New-UninstallKey $Machine 'Fabrikam_is1' @{
            DisplayName = 'Fabrikam'; DisplayVersion = '5.0'
            QuietUninstallString = "`"$System\msiexec.exe`" /SILENT"; UninstallString = "`"$System\msiexec.exe`""
            URLUpdateInfo = 'https://fabrikam.example/download'; URLInfoAbout = 'javascript:alert(1)'
        }
        New-UninstallKey $User 'UserApp' @{
            DisplayName = 'User App'; DisplayVersion = '0.9'; UninstallString = "`"$System\msiexec.exe`" /S"
        }
        New-UninstallKey $User $guid.Replace('1111', '9999') @{ DisplayName = 'Per-User MSI'; DisplayVersion = '1.0'; WindowsInstaller = 1 }
    }

    Context 'Auswahl der Methode' {
        It 'nimmt winget zuerst und nennt MSI als nächste Methode' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' })
            $plan.Method | Should -Be 'Winget'
            $plan.NextMethod | Should -Be 'Msi'
            $plan.Arguments | Should -Be 'uninstall --id Contoso.Tool --exact --source winget --silent --accept-source-agreements --disable-interactivity --scope machine'
        }

        It 'nimmt ohne winget MSI mit unveränderter Produkt-ID, /qn, /norestart und Log' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid" })
            $plan.Method | Should -Be 'Msi'
            $plan.FilePath | Should -Be (Join-Path $System 'msiexec.exe')
            $plan.Arguments | Should -Be "/x $guid /qn /norestart"
            $plan.MsiLog | Should -BeTrue
            $plan.CommandLine | Should -Match '/l\*v'
            $plan.NextMethod | Should -Be 'QuietUninstallString'
        }

        It 'nimmt ohne MSI zuerst QuietUninstallString, dann UninstallString' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1" })
            $plan.Method | Should -Be 'QuietUninstallString'
            $plan.FilePath | Should -Be "$System\msiexec.exe"
            $plan.Arguments | Should -Be '/SILENT'
            $plan.NextMethod | Should -Be 'UninstallString'
            (Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1" }) -Method UninstallString).Arguments | Should -Be ''
        }

        It 'nimmt Remove-AppxPackage für Store-Apps' {
            Mock -ModuleName SoftwareInventory Get-AppxPackageByFamily { [pscustomobject] @{ PackageFullName = 'Contoso.App_1.0.0.0_x64__abc'; Version = '1.0.0.0' } }
            $plan = Get-Plan (New-TestRecord @{ PackageFamilyName = 'Contoso.App_abc' })
            $plan.Method | Should -Be 'Appx'
            $plan.Elevated | Should -BeFalse
            $plan.CommandLine | Should -Be 'Remove-AppxPackage -Package Contoso.App_1.0.0.0_x64__abc'
        }

        It 'respektiert -Method und lehnt nicht verfügbare Methoden ab' {
            $record = New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }
            (Get-Plan $record -Method Msi).Method | Should -Be 'Msi'
            $plan = Get-Plan $record -Method Appx
            $plan.Result | Should -Be 'Unsupported'
            $plan.Message.Code | Should -Be 'PlanMethodNotAvailable'
            $plan.Message.Args[1] | Should -Match 'Winget, Msi'
        }

        It 'meldet NotInstalled, wenn der Eintrag nicht mehr existiert' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Weg" })
            $plan.Result | Should -Be 'NotInstalled'
        }

        It 'lehnt Registry-Pfade außerhalb der Uninstall-Zweige ab' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = 'TestRegistry:\Anderswo\Contoso'; UninstallString = 'C:\evil.exe' })
            $plan.Result | Should -Be 'NotInstalled'
        }

        It 'nutzt nie Befehle aus dem Datensatz, sondern liest die Registry neu' {
            $record = New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1"; QuietUninstallString = 'C:\evil.exe /x' }
            (Get-Plan $record).FilePath | Should -Be "$System\msiexec.exe"
        }

        It 'lehnt ungültige winget-IDs ab' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso Tool; rm'; WingetSource = 'winget' }) -Method Winget
            $plan.Result | Should -Be 'Unsupported'
        }

        It 'bricht ab, wenn winget nicht gefunden wird' {
            Mock -ModuleName SoftwareInventory Get-WingetExecutable { $null }
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' })
            $plan.Result | Should -Be 'Unsupported'
            $plan.Message.Code | Should -Be 'PlanWingetNotFound'
        }
    }

    Context 'Adminrechte' {
        It 'erhöht für Einträge unter HKLM' {
            (Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid" })).Elevated | Should -BeTrue
            (Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1" })).Elevated | Should -BeTrue
        }

        It 'erhöht nie für Einträge unter HKCU, auch nicht bei MSI und winget' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$User\UserApp" })
            $plan.Method | Should -Be 'UninstallString'
            $plan.Elevated | Should -BeFalse
            (Get-Plan (New-TestRecord @{ RegistryKey = "$User\$($guid.Replace('1111', '9999'))" })).Elevated | Should -BeFalse
            $winget = Get-Plan (New-TestRecord @{ RegistryKey = "$User\UserApp"; WingetId = 'User.App'; WingetSource = 'winget' })
            $winget.Elevated | Should -BeFalse
            $winget.Arguments | Should -Match '--scope user$'
        }

        It 'richtet sich nach dem echten Zweig, nicht nach Scope im Datensatz' {
            (Get-Plan (New-TestRecord @{ RegistryKey = "$User\UserApp"; Scope = 'Machine' })).Elevated | Should -BeFalse
        }

        It 'erhöht nicht selbst, wenn der Bereich unbekannt ist (nur winget)' {
            Mock -ModuleName SoftwareInventory Get-WingetInstalledVersion { '3.0' }
            $plan = Get-Plan (New-TestRecord @{ WingetId = 'Only.Winget'; WingetSource = 'winget' })
            $plan.Scope | Should -Be 'Unknown'
            $plan.Elevated | Should -BeFalse
            $plan.Arguments | Should -Not -Match '--scope'
        }

        It 'startet keine für Benutzer beschreibbare Datei mit Adminrechten' {
            Mock -ModuleName SoftwareInventory Test-UserWritablePath { $true }
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1" })
            $plan.Result | Should -Be 'Unsupported'
            $plan.Message.Code | Should -Be 'PlanUninstallerUserWritable'
        }

        It 'führt beschreibbare Dateien aus HKCU ohne Adminrechte aus' {
            Mock -ModuleName SoftwareInventory Test-UserWritablePath { $true }
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$User\UserApp" })
            $plan.Result | Should -BeNullOrEmpty
            $plan.Elevated | Should -BeFalse
        }
    }

    Context 'Aktualisieren' {
        It 'aktualisiert über winget upgrade mit exakter ID, Quelle und Zustimmungen' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }) -Action Update
            $plan.Method | Should -Be 'Winget'
            $plan.Arguments | Should -Be 'upgrade --id Contoso.Tool --exact --source winget --silent --accept-source-agreements --disable-interactivity --accept-package-agreements'
            $plan.Elevated | Should -BeTrue
        }

        It 'liefert ohne winget nur den Herstellerlink (nur http/https)' {
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\Fabrikam_is1" }) -Action Update
            $plan.Result | Should -Be 'ManualUpdateRequired'
            $plan.Method | Should -Be 'VendorLink'
            $plan.VendorUrl | Should -Be 'https://fabrikam.example/download'
            $plan.FilePath | Should -BeNullOrEmpty
        }

        It 'nimmt GitHub-Releases aus dem Katalog als Herstellerlink' {
            New-UninstallKey $Machine '7-Zip' @{ DisplayName = '7-Zip 24.08 (x64)'; DisplayVersion = '24.08'; Publisher = 'Igor Pavlov' }
            $plan = Get-Plan (New-TestRecord @{ Name = '7-Zip 24.08 (x64)'; Publisher = 'Igor Pavlov'; RegistryKey = "$Machine\7-Zip" }) -Action Update
            $plan.VendorUrl | Should -Be 'https://github.com/ip7z/7zip/releases'
        }

        It 'nimmt die lokale Kennung, wenn winget die Katalog-ID nicht genau findet (z. B. Gyan.FFmpeg)' {
            $key = 'Contoso.Tool_Microsoft.Winget.Source_8wekyb3d8bbwe'
            New-UninstallKey $User $key @{ DisplayName = 'Contoso Tool'; DisplayVersion = '7.1.1' }
            $script:Arch = [string] [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
            Mock -ModuleName SoftwareInventory Invoke-WingetCli {
                if (@($Argument) -contains 'Contoso.Tool') { return @{ ExitCode = -1978335212; Lines = @('Kein installiertes Paket gefunden') } }
                @{ ExitCode = 0; Lines = @('Name         ID           Version Verfügbar', '-----------------------------------------', 'Contoso Tool contoso.tool 7.1.1   9.0.2') }
            }
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$User\$key"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }) -Action Update
            $plan.Result | Should -BeNullOrEmpty
            $plan.Arguments | Should -Be "upgrade --id ARP\User\$script:Arch\$key --exact --source winget --silent --accept-source-agreements --disable-interactivity --accept-package-agreements"
            # nur lesend und nie ohne --exact gefragt
            Should -Invoke -ModuleName SoftwareInventory Invoke-WingetCli -Times 2 -Exactly -ParameterFilter { $Argument[0] -eq 'list' -and @($Argument) -contains '--exact' }
        }

        It 'führt nichts aus und nennt die Herstellerseite, wenn winget das Paket gar nicht genau findet' {
            New-UninstallKey $User 'Contoso.Tool_x' @{ DisplayName = 'Contoso Tool'; DisplayVersion = '7.1.1'; URLUpdateInfo = 'https://contoso.example/download' }
            Mock -ModuleName SoftwareInventory Invoke-WingetCli { @{ ExitCode = -1978335212; Lines = @() } }
            $plan = Get-Plan (New-TestRecord @{ RegistryKey = "$User\Contoso.Tool_x"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }) -Action Update
            $plan.Result | Should -Be 'ManualUpdateRequired'
            $plan.Method | Should -Be 'VendorLink'
            $plan.VendorUrl | Should -Be 'https://contoso.example/download'
            $plan.Message.Code | Should -Be 'PlanWingetExactNotFoundLink'
            $plan.FilePath | Should -BeNullOrEmpty
        }

        It 'nimmt die lokale Kennung nicht, wenn winget dort ein anderes Paket oder mehrere zeigt' -ForEach @(
            @{ Case = 'anderes Paket'; Rows = @('Other Other.Tool 1.0') }
            @{ Case = 'mehrere'; Rows = @('A Contoso.Tool 1.0', 'B Contoso.Tool 2.0') }
        ) {
            New-UninstallKey $User 'Contoso.Tool_y' @{ DisplayName = 'Contoso Tool'; DisplayVersion = '7.1.1' }
            $script:Rows = $Rows
            Mock -ModuleName SoftwareInventory Invoke-WingetCli {
                if (@($Argument) -contains 'Contoso.Tool') { return @{ ExitCode = -1978335212; Lines = @() } }
                @{ ExitCode = 0; Lines = @('Name ID Version', '---------------') + @($script:Rows) }
            }
            (Get-Plan (New-TestRecord @{ RegistryKey = "$User\Contoso.Tool_y"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }) -Action Update).Result | Should -Be 'ManualUpdateRequired'
        }

        It 'prüft Store-Pakete nicht, damit keiner Store-Vereinbarung zugestimmt wird' {
            Mock -ModuleName SoftwareInventory Test-StoreAgreementAccepted { $true }
            Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = '9NBLGGH4NNS1'; WingetSource = 'msstore' }) -Action Update | Out-Null
            Should -Invoke -ModuleName SoftwareInventory Invoke-WingetCli -Times 0 -Exactly
        }

        It 'lehnt andere Methoden als winget ab' {
            (Get-Plan (New-TestRecord @{ RegistryKey = "$Machine\$guid"; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }) -Action Update -Method Msi).Result | Should -Be 'Unsupported'
        }
    }
}

Describe 'ConvertTo-ArgumentString' {
    It 'setzt Anführungszeichen nur wo nötig und maskiert nach CommandLineToArgvW' {
        InModuleScope SoftwareInventory { ConvertTo-ArgumentString @('a', 'b c', 'x"y', 'C:\Pfad mit\', '') } |
            Should -Be 'a "b c" "x\"y" "C:\Pfad mit\\" ""'
    }
}
