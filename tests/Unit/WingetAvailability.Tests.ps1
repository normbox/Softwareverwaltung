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
        $s.Message | Should -Match 'App Installer'
        $s.InstallUrl | Should -Match '^https://apps\.microsoft\.com/'
    }

    It 'nennt das fehlende Modul' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $WingetPath }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $null }
        $s = Test-WingetAvailability
        $s.Available | Should -BeFalse
        $s.ModuleAvailable | Should -BeFalse
        $s.Message | Should -Match 'Microsoft\.WinGet\.Client'
        $s.InstallUrl | Should -BeNullOrEmpty
    }

    It 'meldet, wenn beides fehlt, dass das Inventar nur aus Registry und Store kommt' {
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { $null }
        Mock -ModuleName SoftwareInventory Get-Command -ParameterFilter { $Name -eq 'Get-WinGetPackage' } { $null }
        $s = Test-WingetAvailability
        $s.Available | Should -BeFalse
        $s.Message | Should -Match 'nur aus Registry und Store'
    }
}
