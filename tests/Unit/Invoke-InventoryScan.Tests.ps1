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

    It 'sucht nicht, solange der Hauptschalter aus ist, auch wenn alles eingerichtet ist' {
        Set-InventorySetting -Enable Process -ScanPath '%USERPROFILE%' -ScanDrive C | Out-Null
        (Get-InventorySetting).PortableSearch.Enabled | Should -BeFalse
        @(Invoke-InventoryScan).Name | Should -Be @('Installiert')
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'sucht nicht bei eingeschaltetem Hauptschalter ohne Spuren, Ordner und Laufwerke' {
        Set-InventorySetting -PortableSearch $true | Out-Null
        @(Invoke-InventoryScan -WarningVariable w).Name | Should -Be @('Installiert')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'sucht portable Programme bei Hauptschalter an, sobald <Case> eingerichtet ist, und gibt die installierten weiter' -TestCases @(
        @{ Case = 'eine Nutzungsspur'; Arguments = @{ Enable = 'Process' } }
        @{ Case = 'ein Ordner'; Arguments = @{ ScanPath = '%USERPROFILE%' } }
        @{ Case = 'ein Laufwerk'; Arguments = @{ ScanDrive = 'C' } }
    ) {
        Set-InventorySetting @Arguments -PortableSearch $true | Out-Null
        $r = @(Invoke-InventoryScan)
        $r.Name | Should -Be @('Installiert', 'Portabel')
        Should -Invoke -ModuleName SoftwareInventory Get-SoftwareInventory -Times 1 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 1 -Exactly -ParameterFilter { $Inventory.Count -eq 1 -and $Inventory[0].Name -eq 'Installiert' }
    }
}

Describe 'Hauptschalter PortableSearch' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true } }
    }

    It 'ist standardmäßig aus, wird gespeichert und von keiner Vorlage eingeschaltet' {
        (Get-InventorySetting).PortableSearch.Enabled | Should -BeFalse
        (Set-InventorySetting -Preset Thorough).PortableSearch.Enabled | Should -BeFalse
        Set-InventorySetting -PortableSearch $true | Out-Null
        (Get-InventorySetting).PortableSearch.Enabled | Should -BeTrue
        (Set-InventorySetting -Reset).PortableSearch.Enabled | Should -BeFalse
    }

    It 'behält Spuren und Ordner, wenn er ausgeschaltet wird' {
        Set-InventorySetting -PortableSearch $true -Enable UserAssist -ScanPath 'D:\Tools' | Out-Null
        $s = Set-InventorySetting -PortableSearch $false
        $s.Traces.UserAssist | Should -BeTrue
        $s.FileScan.Paths | Should -Be @('D:\Tools')
    }
}
