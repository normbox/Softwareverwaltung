BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    $script:WingetPath = 'C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_1_x64__8wekyb3d8bbwe\winget.exe'
    $script:Command = [pscustomobject] @{ Name = 'Get-WinGetPackage'; Module = [pscustomobject] @{ Version = [version] '1.29.380' } }
}

Describe 'Test-WingetAvailability' {
    It 'meldet verfügbar, wenn winget.exe und das Modul da sind' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $WingetPath }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $Command }
        $s = Test-WingetAvailability
        $s.PSObject.TypeNames | Should -Contain 'SoftwareInventory.WingetStatus'
        $s.Available | Should -BeTrue
        $s.CliPath | Should -Be $WingetPath
        $s.ModuleVersion | Should -Be '1.29.380'
        $s.Message | Should -BeNullOrEmpty
        $s.InstallUrl | Should -BeNullOrEmpty
    }

    It 'nennt fehlendes winget.exe mit Folgen und Store-Link' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $null }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $Command }
        $s = Test-WingetAvailability
        $s.Available | Should -BeFalse
        $s.CliAvailable | Should -BeFalse
        $s.ModuleAvailable | Should -BeTrue
        $s.Message.Code | Should -Be 'WingetStatusCliMissing'
        $s.InstallUrl | Should -Match '^https://apps\.microsoft\.com/'
    }

    It 'nennt das fehlende Modul' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $WingetPath }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $null }
        $s = Test-WingetAvailability
        $s.Available | Should -BeFalse
        $s.ModuleAvailable | Should -BeFalse
        $s.Message.Code | Should -Be 'WingetStatusModuleMissing'
        $s.InstallUrl | Should -BeNullOrEmpty
    }

    It 'meldet, wenn beides fehlt, dass das Inventar nur aus Registry und Store kommt' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $null }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $null }
        $s = Test-WingetAvailability
        $s.Available | Should -BeFalse
        $s.Message.Code | Should -Be 'WingetStatusMissing'
    }
}

Describe 'Install-WingetPackageManager' {
    BeforeEach {
        $appData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $appData }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Repair-WinGetPackageManager' } { [pscustomobject] @{ Name = 'Repair-WinGetPackageManager' } }
        Mock -ModuleName SoftwareInventory Invoke-WingetRepair { 'repariert' }
        $script:wingetInstalled = $false
        Mock -ModuleName SoftwareInventory Test-WingetAvailability {
            [pscustomobject] @{ Available = $script:wingetInstalled; CliAvailable = $script:wingetInstalled; ModuleVersion = '1.29.380'; Message = 'winget.exe fehlt' }
        }
    }

    It 'zeigt mit -WhatIf, was passiert, führt nichts aus und protokolliert nicht' {
        $r = Install-WingetPackageManager -WhatIf
        $r.Result | Should -Be 'Planned'
        $r.CommandLine | Should -Be 'Repair-WinGetPackageManager -Latest'
        $r.Elevated | Should -BeFalse
        $r.Message.Code | Should -Be 'WingetInstallDescription'
        Should -Invoke -ModuleName SoftwareInventory Invoke-WingetRepair -Times 0
        Get-ActionLog | Should -BeNullOrEmpty
    }

    It 'installiert, prüft den Erfolg und protokolliert Start und Abschluss' {
        Mock -ModuleName SoftwareInventory Invoke-WingetRepair { $script:wingetInstalled = $true; 'repariert' }
        $r = Install-WingetPackageManager -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        $r.PresentBefore | Should -BeFalse
        $r.PresentAfter | Should -BeTrue
        $log = Get-ActionLog -Action InstallWinget
        $log.Result | Should -Be 'Succeeded'
    }

    It 'meldet NotVerified, wenn winget danach noch fehlt' {
        (Install-WingetPackageManager -Confirm:$false).Result | Should -Be 'NotVerified'
    }

    It 'meldet Fehler beim Herunterladen als Failed' {
        Mock -ModuleName SoftwareInventory Invoke-WingetRepair { throw 'Keine Verbindung' }
        $r = Install-WingetPackageManager -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'WingetInstallFailed'
        $r.Message.Args[0] | Should -Match 'Keine Verbindung'
        (Get-ActionLog).Result | Should -Be 'Failed'
    }

    It 'verlangt eine Bestätigung' {
        (Get-Command Install-WingetPackageManager).ScriptBlock.Attributes.Where({ $_ -is [System.Management.Automation.CmdletBindingAttribute] }).ConfirmImpact | Should -Be 'High'
    }
}
