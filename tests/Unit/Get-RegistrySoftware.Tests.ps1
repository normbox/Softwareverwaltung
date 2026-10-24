BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Get-RegistrySoftware' {
    BeforeAll {
        function New-UninstallKey {
            param([string] $Root, [string] $Name, [hashtable] $Values)
            $key = New-Item -Path $Root -Name $Name -Force
            foreach ($v in $Values.GetEnumerator()) {
                $type = if ($v.Value -is [int]) { 'DWord' } else { 'String' }
                New-ItemProperty -Path $key.PSPath -Name $v.Key -Value $v.Value -PropertyType $type | Out-Null
            }
        }

        $machine = 'TestRegistry:\Machine'
        $user = 'TestRegistry:\User'
        New-Item -Path $machine, $user -Force | Out-Null

        New-UninstallKey $machine '{11111111-2222-3333-4444-555555555555}' @{
            DisplayName = 'Contoso Tool'; DisplayVersion = '2.1.0'; Publisher = 'Contoso'
            WindowsInstaller = 1; InstallDate = '20260115'; UninstallString = 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}'
        }
        New-UninstallKey $machine 'Fabrikam Editor_is1' @{
            DisplayName = ' Fabrikam Editor '; DisplayVersion = '5.0'; InstallDate = 'unbekannt'
            QuietUninstallString = '"C:\Program Files\Fabrikam\unins000.exe" /SILENT'
        }
        New-UninstallKey $machine 'NoName' @{ DisplayVersion = '1.0' }
        New-UninstallKey $machine 'SysComp' @{ DisplayName = 'Hidden Runtime'; SystemComponent = 1 }
        New-UninstallKey $machine 'Child' @{ DisplayName = 'Contoso Tool Plugin'; ParentKeyName = 'Contoso' }
        New-UninstallKey $machine 'Hotfix' @{ DisplayName = 'Update for Contoso'; ReleaseType = 'Hotfix' }
        New-UninstallKey $machine 'KB' @{ DisplayName = 'Security Update for Something (KB5001234)' }
        New-UninstallKey $user 'UserApp' @{ DisplayName = 'User App'; DisplayVersion = '0.9' }

        $result = InModuleScope SoftwareInventory -Parameters @{ M = $machine; U = $user } {
            Get-RegistrySoftware -Location @(
                @{ Path = $M; Scope = 'Machine'; Architecture = 'X64' }
                @{ Path = $U; Scope = 'User'; Architecture = $null }
                @{ Path = 'TestRegistry:\Missing'; Scope = 'Machine'; Architecture = 'X86' }
            )
        }
    }

    It 'liefert nur eigenständige Programme' {
        $result.Name | Sort-Object | Should -Be @('Contoso Tool', 'Fabrikam Editor', 'User App')
    }

    It 'erkennt MSI-Installationen samt ProductCode' {
        $msi = $result | Where-Object Name -eq 'Contoso Tool'
        $msi.InstallType | Should -Be 'MSI'
        $msi.ProductCode | Should -Be '{11111111-2222-3333-4444-555555555555}'
        $msi.InstallDate | Should -Be '2026-01-15'
        $msi.Scope | Should -Be 'Machine'
        $msi.Architecture | Should -Be 'X64'
        $msi.Sources | Should -Be @('Registry')
    }

    It 'behandelt EXE-Installationen und ungültige Datumswerte' {
        $exe = $result | Where-Object Name -eq 'Fabrikam Editor'
        $exe.InstallType | Should -Be 'EXE'
        $exe.ProductCode | Should -BeNullOrEmpty
        $exe.InstallDate | Should -BeNullOrEmpty
        $exe.QuietUninstallString | Should -Match 'unins000\.exe'
        $exe.RegistryKey | Should -Be 'TestRegistry:\Machine\Fabrikam Editor_is1'
    }

    It 'setzt den Bereich für Benutzer-Installationen' {
        ($result | Where-Object Name -eq 'User App').Scope | Should -Be 'User'
    }
}

Describe 'New-SoftwareRecord' {
    It 'enthält alle Schemafelder' {
        $r = InModuleScope SoftwareInventory { New-SoftwareRecord -Name 'X' -Source Appx }
        $r.PSObject.TypeNames[0] | Should -Be 'SoftwareInventory.SoftwareRecord'
        $r.PSObject.Properties.Name | Should -Contain 'WingetId'
        $r.Sources | Should -Be @('Appx')
    }

    It 'lehnt unbekannte Felder ab' {
        { InModuleScope SoftwareInventory { New-SoftwareRecord -Name 'X' -Source Appx -Property @{ Foo = 1 } } } |
            Should -Throw '*Foo*'
    }
}
