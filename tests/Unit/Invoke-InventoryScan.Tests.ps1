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

    It 'sucht nicht und meldet nichts, solange der Hauptschalter aus ist, auch wenn alles gewählt ist' {
        Set-InventorySetting -Enable Process -ScanPath '%USERPROFILE%' -ScanDrive C | Out-Null
        (Get-InventorySetting).PortableSearch.Enabled | Should -BeFalse
        @(Invoke-InventoryScan -WarningVariable w).Name | Should -Be @('Installiert')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'meldet bei eingeschalteter Suche ohne Laufwerk, Ordner und Spur einen Hinweis und sucht nicht' {
        Set-InventorySetting -PortableSearch $true | Out-Null
        @(Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue).Name | Should -Be @('Installiert')
        "$w" | Should -Match 'weder ein Laufwerk'
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'sucht ohne Laufwerk und Ordner nur über Nutzungsspuren und meldet das' {
        Set-InventorySetting -PortableSearch $true -Enable Process | Out-Null
        @(Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue).Name | Should -Be @('Installiert', 'Portabel')
        "$w" | Should -Match 'keine Dateien durchsucht'
    }

    It 'sucht portable Programme bei <Case> ohne Hinweis und gibt die installierten weiter' -TestCases @(
        @{ Case = 'gewähltem Ordner'; Arguments = @{ ScanPath = '%USERPROFILE%' } }
        @{ Case = 'gewähltem Laufwerk'; Arguments = @{ ScanDrive = 'C' } }
    ) {
        Set-InventorySetting @Arguments -PortableSearch $true | Out-Null
        @(Invoke-InventoryScan -WarningVariable w).Name | Should -Be @('Installiert', 'Portabel')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-SoftwareInventory -Times 1 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 1 -Exactly -ParameterFilter { $Inventory.Count -eq 1 -and $Inventory[0].Name -eq 'Installiert' }
    }
}

Describe 'Kein Dateiscan ohne Laufwerk oder Ordner' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-SoftwareInventory { }
        Mock -ModuleName SoftwareInventory Find-ExecutableFile { }
        foreach ($t in 'UserAssist', 'Process', 'Autostart', 'ScheduledTask') { Mock -ModuleName SoftwareInventory "Get-${t}Trace" { } }
    }

    It 'Get-PortableSoftware ruft ohne Laufwerk und Ordner keinen Dateiscan auf, auch mit Spuren' {
        Get-PortableSoftware -Trace Process, UserAssist -Inventory @() | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
        Should -Invoke -ModuleName SoftwareInventory Get-ProcessTrace -Times 1 -Exactly
    }

    It 'der vollständige Scan durchsucht ohne Laufwerk und Ordner keine Dateien' {
        Set-InventorySetting -PortableSearch $true -Enable UserAssist, Process, Autostart, ScheduledTask -IncludeTemp $true | Out-Null
        Invoke-InventoryScan -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
    }

    It 'der vollständige Scan durchsucht genau die gewählten Laufwerke und Ordner' {
        Set-InventorySetting -PortableSearch $true -ScanDrive D -ScanPath 'E:\Tools' | Out-Null
        Invoke-InventoryScan | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { @($Root) -contains 'D:\' -and @($Root) -contains 'E:\Tools' -and @($Root).Count -eq 2 }
    }
}

Describe 'Hauptschalter PortableSearch' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true } }
    }

    It 'ist standardmäßig aus, ohne vorausgewählte Laufwerke, und wird von keiner Vorlage eingeschaltet' {
        $s = Get-InventorySetting
        $s.PortableSearch.Enabled | Should -BeFalse
        $s.FileScan.Drives | Should -BeNullOrEmpty
        (Set-InventorySetting -Preset Thorough).PortableSearch.Enabled | Should -BeFalse
        (Get-SettingPreset -Preset Quick).PSObject.Properties.Name | Should -Not -Contain 'PortableSearch'
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
