BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Invoke-InventoryScan' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        $script:installed = InModuleScope SoftwareInventory { New-SoftwareRecord -Name 'Installiert' -Source Registry -Property @{ Version = '1.0' } }
        $script:portable = InModuleScope SoftwareInventory { New-SoftwareRecord -Name 'Portabel' -Source Portable -Property @{ Version = '2.0' } }
        Mock -ModuleName SoftwareInventory Get-SoftwareInventory { $script:installed }
        Mock -ModuleName SoftwareInventory Get-PortableSoftware { $script:portable }
    }

    It 'liefert nur installierte Programme und keine Warnung, wenn die Suche nach portablen Programmen nicht eingerichtet ist' {
        $r = @(Invoke-InventoryScan -WarningVariable w)
        $r.Name | Should -Be @('Installiert')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'sucht portable Programme, sobald <Case> eingerichtet ist, und gibt die installierten weiter' -TestCases @(
        @{ Case = 'eine Nutzungsspur'; Arguments = @{ Enable = 'Process' } }
        @{ Case = 'ein Ordner'; Arguments = @{ ScanPath = '%USERPROFILE%' } }
        @{ Case = 'ein Laufwerk'; Arguments = @{ ScanDrive = 'C' } }
    ) {
        Set-InventorySetting @Arguments | Out-Null
        $r = @(Invoke-InventoryScan)
        $r.Name | Should -Be @('Installiert', 'Portabel')
        Should -Invoke -ModuleName SoftwareInventory Get-SoftwareInventory -Times 1 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 1 -Exactly -ParameterFilter { $Inventory.Count -eq 1 -and $Inventory[0].Name -eq 'Installiert' }
    }
}
