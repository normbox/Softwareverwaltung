BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Einstellungen' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
    }

    It 'ist ohne Datei vollständig aus' {
        $s = Get-InventorySetting
        $s.Sources.PSObject.Properties.Value | Should -Not -Contain $true
        $s.Traces.PSObject.Properties.Value | Should -Not -Contain $true
        $s.FileScan.Paths | Should -BeNullOrEmpty
        $s.FileScan.Drives | Should -BeNullOrEmpty
        $s.FileScan.IncludeTemp | Should -BeFalse
        $s.FileScan.ComputeHash | Should -BeFalse
        $s.Usage | Should -BeNullOrEmpty
    }

    It 'schaltet Bereiche einzeln ein und aus und speichert sie' {
        Set-InventorySetting -Enable RegistryMachine, UserAssist | Out-Null
        Set-InventorySetting -Enable Winget -Disable UserAssist | Out-Null
        $s = Get-InventorySetting
        $s.Sources.RegistryMachine | Should -BeTrue
        $s.Sources.Winget | Should -BeTrue
        $s.Sources.RegistryUser | Should -BeFalse
        $s.Traces.UserAssist | Should -BeFalse
        Test-Path $settingsFile | Should -BeTrue
    }

    It 'belegt mit Vorlage Quick vor und lässt danach Einzeländerungen zu' {
        $s = Set-InventorySetting -Preset Quick -Disable ScheduledTask
        $s.Sources.PSObject.Properties.Value | Should -Not -Contain $false
        $s.Traces.ScheduledTask | Should -BeFalse
        $s.Traces.UserAssist | Should -BeTrue
        $s.FileScan.Paths | Should -Be @('%USERPROFILE%')
        $s.FileScan.ComputeHash | Should -BeFalse
    }

    It 'belegt mit Vorlage Thorough Laufwerke, Temp und Hash vor' {
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true }; [pscustomobject] @{ Drive = 'E:'; IsDefault = $false } }
        $s = Set-InventorySetting -Preset Thorough
        $s.FileScan.Drives | Should -Be @('C:')
        $s.FileScan.IncludeTemp | Should -BeTrue
        $s.FileScan.ComputeHash | Should -BeTrue
    }

    It 'normalisiert Laufwerke und ersetzt Ordnerlisten' {
        Set-InventorySetting -ScanDrive d, 'E:\' -ScanPath 'C:\Tools' | Out-Null
        $s = Get-InventorySetting
        $s.FileScan.Drives | Should -Be @('D:', 'E:')
        $s.FileScan.Paths | Should -Be @('C:\Tools')
    }

    It 'speichert Privat/Firma nur als Information' {
        $s = Set-InventorySetting -Usage Company
        $s.Usage | Should -Be 'Company'
        $s.Sources.PSObject.Properties.Value | Should -Not -Contain $true
        $s.Traces.PSObject.Properties.Value | Should -Not -Contain $true
    }

    It 'setzt mit -Reset alles zurück, behält aber Usage' {
        Set-InventorySetting -Preset Quick -Usage Private | Out-Null
        $s = Set-InventorySetting -Reset
        $s.Sources.PSObject.Properties.Value | Should -Not -Contain $true
        $s.FileScan.Paths | Should -BeNullOrEmpty
        $s.Usage | Should -Be 'Private'
    }

    It 'ergänzt fehlende Werte in der Datei mit aus und ignoriert unbekannte' {
        '{"Sources":{"Appx":true,"Fremd":true},"Usage":"Irgendwas"}' | Set-Content $settingsFile
        $s = Get-InventorySetting
        $s.Sources.Appx | Should -BeTrue
        $s.Sources.RegistryMachine | Should -BeFalse
        $s.Sources.PSObject.Properties.Name | Should -Not -Contain 'Fremd'
        $s.Usage | Should -BeNullOrEmpty
    }

    It 'hat ohne Angabe keine eigenen Ausschlüsse und SmartExclusions an' {
        $s = Get-InventorySetting
        $s.FileScan.ExcludePaths | Should -BeNullOrEmpty
        $s.FileScan.SmartExclusions | Should -BeTrue
        '{"FileScan":{"Paths":["C:\\Tools"]}}' | Set-Content $settingsFile
        (Get-InventorySetting).FileScan.SmartExclusions | Should -BeTrue
    }

    It 'speichert eigene Ausschlüsse und SmartExclusions; Vorlagen ändern sie nicht, Reset setzt zurück' {
        Set-InventorySetting -ExcludePath '%USERPROFILE%\Builds', 'D:\Archiv' -SmartExclusions $false | Out-Null
        $s = Get-InventorySetting
        $s.FileScan.ExcludePaths | Should -Be @('%USERPROFILE%\Builds', 'D:\Archiv')
        $s.FileScan.SmartExclusions | Should -BeFalse

        $s = Set-InventorySetting -Preset Quick
        $s.FileScan.ExcludePaths | Should -Be @('%USERPROFILE%\Builds', 'D:\Archiv')
        $s.FileScan.SmartExclusions | Should -BeFalse

        $s = Set-InventorySetting -Reset
        $s.FileScan.ExcludePaths | Should -BeNullOrEmpty
        $s.FileScan.SmartExclusions | Should -BeTrue
    }

    It 'hat alle externen Dienste standardmäßig aus und schaltet sie einzeln' {
        (Get-InventorySetting).Services.PSObject.Properties.Value | Should -Not -Contain $true
        $s = Set-InventorySetting -Enable GitHub
        $s.Services.GitHub | Should -BeTrue
        $s.Services.NVD | Should -BeFalse
        (Get-InventorySetting).Services.GitHub | Should -BeTrue
        (Set-InventorySetting -Disable GitHub).Services.GitHub | Should -BeFalse
    }

    It 'hat den Wiederherstellungspunkt standardmäßig aus und schaltet ihn einzeln, nie über Vorlagen' {
        (Get-InventorySetting).Actions.RestorePoint | Should -BeFalse
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true } }
        (Set-InventorySetting -Preset Thorough).Actions.RestorePoint | Should -BeFalse
        (Set-InventorySetting -Enable RestorePoint).Actions.RestorePoint | Should -BeTrue
        (Get-InventorySetting).Actions.RestorePoint | Should -BeTrue
        (Set-InventorySetting -Reset).Actions.RestorePoint | Should -BeFalse
    }

    It 'hat 30 Tage und 100 MB als Grenzen für Logs und speichert eigene Werte' {
        $s = Get-InventorySetting
        $s.Maintenance.LogRetentionDays | Should -Be 30
        $s.Maintenance.LogMaxSizeMB | Should -Be 100
        Set-InventorySetting -LogRetentionDays 7 -LogMaxSizeMB 20 | Out-Null
        $s = Get-InventorySetting
        $s.Maintenance.LogRetentionDays | Should -Be 7
        $s.Maintenance.LogMaxSizeMB | Should -Be 20
        { Set-InventorySetting -LogRetentionDays 0 } | Should -Throw
    }

    It 'ignoriert ungültige Grenzen in der Datei' {
        '{"Maintenance":{"LogRetentionDays":-5,"LogMaxSizeMB":"viel"}}' | Set-Content $settingsFile
        $s = Get-InventorySetting
        $s.Maintenance.LogRetentionDays | Should -Be 30
        $s.Maintenance.LogMaxSizeMB | Should -Be 100
    }

    It 'schaltet externe Dienste über keine Vorlage ein' {
        foreach ($preset in 'Quick', 'Thorough') {
            Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true } }
            (Set-InventorySetting -Preset $preset).Services.PSObject.Properties.Value | Should -Not -Contain $true
        }
    }

    It 'liefert Vorlagenwerte ohne zu speichern und ohne Dienste oder Aktionen' {
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'D:'; IsDefault = $true } }
        $quick = Get-SettingPreset -Preset Quick
        $thorough = Get-SettingPreset -Preset Thorough

        Test-Path $settingsFile | Should -BeFalse
        $quick.Enable | Should -Contain 'Winget'
        $quick.Enable | Should -Contain 'UserAssist'
        foreach ($name in 'WingetSearch', 'GitHub', 'NVD', 'KEV', 'EPSS', 'RestorePoint') {
            $quick.Enable + $thorough.Enable | Should -Not -Contain $name
        }
        $quick.FileScan.Paths | Should -Be @('%USERPROFILE%')
        $thorough.FileScan.Drives | Should -Be @('D:')
        $thorough.FileScan.ComputeHash | Should -BeTrue
    }

    It 'Get-SoftwareInventory liest ohne aktivierte Quelle nichts' {
        Mock -ModuleName SoftwareInventory Get-RegistrySoftware { throw 'darf nicht gelesen werden' }
        Mock -ModuleName SoftwareInventory Get-AppxSoftware { throw 'darf nicht gelesen werden' }
        Mock -ModuleName SoftwareInventory Get-WingetSoftware { throw 'darf nicht gelesen werden' }
        $r = Get-SoftwareInventory -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        "$w" | Should -Match 'Keine Quelle aktiviert'
    }

    It 'Get-SoftwareInventory liest nur die aktivierten Registry-Zweige' {
        Set-InventorySetting -Enable RegistryUser | Out-Null
        Mock -ModuleName SoftwareInventory Get-RegistrySoftware { }
        Mock -ModuleName SoftwareInventory Get-AppxSoftware { throw 'darf nicht gelesen werden' }
        Mock -ModuleName SoftwareInventory Get-WingetSoftware { throw 'darf nicht gelesen werden' }
        Get-SoftwareInventory | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Get-RegistrySoftware -Times 1 -Exactly -ParameterFilter {
            @($Location).Count -eq 1 -and $Location[0].Scope -eq 'User'
        }
    }
}
