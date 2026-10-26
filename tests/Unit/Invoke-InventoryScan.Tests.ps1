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
        Set-InventorySetting -TraceSearch $true -FileSearch $true -Enable Process -ScanMode Folders -ScanPath '%USERPROFILE%' | Out-Null
        (Get-InventorySetting).PortableSearch.Enabled | Should -BeFalse
        @(Invoke-InventoryScan -WarningVariable w).Name | Should -Be @('Installiert')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'meldet bei eingeschalteter Suche ohne Nutzungsspuren und Dateisuche einen Hinweis und sucht nicht' {
        Set-InventorySetting -PortableSearch $true -Enable Process -ScanMode Folders -ScanPath '%USERPROFILE%' | Out-Null
        @(Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue).Name | Should -Be @('Installiert')
        "$w" | Should -Match 'weder Nutzungsspuren noch Dateisuche'
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'Nutzungsspuren wirken unabhängig von der Dateisuche' {
        Set-InventorySetting -PortableSearch $true -TraceSearch $true -Enable Process, UserAssist -ScanMode Folders -ScanPath '%USERPROFILE%' | Out-Null
        @(Invoke-InventoryScan -WarningVariable w).Name | Should -Be @('Installiert', 'Portabel')
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 1 -Exactly -ParameterFilter {
            @($Trace) -contains 'Process' -and @($Trace) -contains 'UserAssist' -and -not $Path -and -not $Drive
        }
    }

    It 'Dateisuche wirkt unabhängig von den Nutzungsspuren' {
        Set-InventorySetting -PortableSearch $true -FileSearch $true -Enable Process -ScanMode Folders -ScanPath 'D:\Tools' | Out-Null
        Invoke-InventoryScan | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 1 -Exactly -ParameterFilter {
            -not $Trace -and @($Path) -eq 'D:\Tools' -and -not $Drive
        }
    }

    It 'meldet eingeschaltete Nutzungsspuren ohne gewählte Spur' {
        Set-InventorySetting -PortableSearch $true -TraceSearch $true | Out-Null
        Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        "$w" | Should -Match 'keine der Spuren'
        Should -Invoke -ModuleName SoftwareInventory Get-PortableSoftware -Times 0
    }

    It 'sucht bei Dateisuche ohne Laufwerk/Ordner nur über Nutzungsspuren und meldet das' {
        Set-InventorySetting -PortableSearch $true -TraceSearch $true -FileSearch $true -Enable Process | Out-Null
        @(Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue).Name | Should -Be @('Installiert', 'Portabel')
        "$w" | Should -Match 'keine Dateien durchsucht'
    }

    It 'sucht portable Programme bei <Case> ohne Hinweis und gibt die installierten weiter' -TestCases @(
        @{ Case = 'gewähltem Ordner'; Arguments = @{ ScanMode = 'Folders'; ScanPath = '%USERPROFILE%' } }
        @{ Case = 'gewähltem Laufwerk'; Arguments = @{ ScanMode = 'Drives'; ScanDrive = 'C' } }
    ) {
        Set-InventorySetting @Arguments -PortableSearch $true -FileSearch $true | Out-Null
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
        Mock -ModuleName SoftwareInventory Test-ScanRoot { $true }
        foreach ($t in 'UserAssist', 'Process', 'Autostart', 'ScheduledTask') { Mock -ModuleName SoftwareInventory "Get-${t}Trace" { } }
    }

    It 'Get-PortableSoftware ruft ohne Laufwerk und Ordner keinen Dateiscan auf, auch mit Spuren' {
        Get-PortableSoftware -Trace Process, UserAssist -Inventory @() | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
        Should -Invoke -ModuleName SoftwareInventory Get-ProcessTrace -Times 1 -Exactly
    }

    It 'der vollständige Scan durchsucht ohne Laufwerk und Ordner keine Dateien' {
        Set-InventorySetting -PortableSearch $true -TraceSearch $true -FileSearch $true -Enable UserAssist, Process, Autostart, ScheduledTask -IncludeTemp $true | Out-Null
        Invoke-InventoryScan -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
    }

    It 'der vollständige Scan durchsucht bei ausgeschalteter Dateisuche keine Dateien, auch mit Laufwerk' {
        Set-InventorySetting -PortableSearch $true -TraceSearch $true -Enable Process -ScanMode Drives -ScanDrive D | Out-Null
        Invoke-InventoryScan -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
    }

    It 'durchsucht nur die Liste der aktiven Option <Mode>; die andere bleibt gespeichert, wird aber nicht genutzt' -TestCases @(
        @{ Mode = 'Drives'; Expected = 'D:\' }
        @{ Mode = 'Folders'; Expected = 'E:\Tools' }
    ) {
        Set-InventorySetting -PortableSearch $true -FileSearch $true -ScanDrive D -ScanPath 'E:\Tools' -ScanMode $Mode | Out-Null
        Invoke-InventoryScan | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { @($Root).Count -eq 1 -and @($Root)[0] -eq $Expected }
        $s = Get-InventorySetting
        $s.FileScan.Drives | Should -Be @('D:')
        $s.FileScan.Paths | Should -Be @('E:\Tools')
    }

    It 'durchsucht ohne gewählte Option keine Dateien, auch wenn Listen gespeichert sind' {
        Set-InventorySetting -PortableSearch $true -FileSearch $true -ScanDrive D -ScanPath 'E:\Tools' -ScanMode None | Out-Null
        Invoke-InventoryScan -WarningVariable w -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
        "$w" | Should -Match 'keine Dateien durchsucht'
    }

    It 'durchsucht bei gewählter Option mit leerer Liste keine Dateien' {
        Set-InventorySetting -PortableSearch $true -FileSearch $true -ScanMode Folders -ScanDrive D | Out-Null
        Invoke-InventoryScan -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0
    }

    It 'Get-PortableSoftware ohne Parameter nutzt ebenfalls nur die aktive Option und die Unterschalter' {
        Set-InventorySetting -ScanDrive D -ScanPath 'E:\Tools' -ScanMode Folders -Enable Process | Out-Null
        Get-PortableSoftware -Inventory @() -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 0          # Dateisuche aus
        Should -Invoke -ModuleName SoftwareInventory Get-ProcessTrace -Times 0             # Nutzungsspuren aus
        Set-InventorySetting -FileSearch $true | Out-Null
        Get-PortableSoftware -Inventory @() | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { @($Root).Count -eq 1 -and @($Root)[0] -eq 'E:\Tools' }
    }

    It 'überspringt ein nicht verbundenes Laufwerk mit Hinweis statt Fehler' {
        Mock -ModuleName SoftwareInventory Test-ScanRoot { $Path -ne 'Q:\' }
        Get-PortableSoftware -Drive Q, D -Inventory @() -WarningVariable w -WarningAction SilentlyContinue -ErrorVariable e | Out-Null
        "$w" | Should -Match 'Laufwerk Q: ist nicht verbunden'
        $e | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Find-ExecutableFile -Times 1 -Exactly -ParameterFilter { @($Root).Count -eq 1 -and @($Root)[0] -eq 'D:\' }
    }

    It 'meldet Spuren auf nicht erreichbare Laufwerke als Treffer „Pfad nicht erreichbar“, veraltete Spuren auf vorhandenen Laufwerken nicht' {
        Mock -ModuleName SoftwareInventory Get-ProcessTrace {
            [pscustomobject] @{ Path = 'Q:\PortableApps\Tool\tool.exe'; Evidence = 'Process'; LastRun = $null; RunCount = $null }
            [pscustomobject] @{ Path = 'C:\GibtEsNicht\weg.exe'; Evidence = 'Process'; LastRun = $null; RunCount = $null }
        }
        Mock -ModuleName SoftwareInventory Get-UserAssistTrace {
            [pscustomobject] @{ Path = 'Q:\PortableApps\Tool\tool.exe'; Evidence = 'UserAssist'; LastRun = '2026-10-01T10:00:00Z'; RunCount = 7 }
        }
        Mock -ModuleName SoftwareInventory Test-PathRootReachable { -not $Path.StartsWith('Q:') }
        $r = @(Get-PortableSoftware -Trace Process, UserAssist -Inventory @())
        $r.Count | Should -Be 1
        $r[0].Name | Should -Be 'tool'
        $r[0].FilePath | Should -Be 'Q:\PortableApps\Tool\tool.exe'
        $r[0].Flags | Should -Contain 'PathUnreachable'
        $r[0].Evidence | Should -Be @('Process', 'UserAssist')
        $r[0].RunCount | Should -Be 7
    }

    It 'die Ampel nennt bei solchen Treffern den Grund „Pfad nicht erreichbar“' {
        $record = InModuleScope SoftwareInventory {
            New-SoftwareRecord -Name 'tool' -Source Portable -Property @{ FilePath = 'Q:\PortableApps\Tool\tool.exe'; Flags = [string[]] @('PathUnreachable') }
        }
        $rating = $record | Get-SecurityRating
        $rating.Reasons[0] | Should -Match '^Pfad nicht erreichbar'
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

Describe 'Option „Wo suchen“ (FileScan.Mode)' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Get-ScanDrive { [pscustomobject] @{ Drive = 'C:'; IsDefault = $true } }
    }

    It 'ist anfangs ohne Option und ohne Einträge' {
        $s = Get-InventorySetting
        $s.FileScan.Mode | Should -BeNullOrEmpty
        $s.FileScan.Paths | Should -BeNullOrEmpty
        $s.FileScan.Drives | Should -BeNullOrEmpty
    }

    It 'übernimmt ältere Einstellungen ohne Option: <Case>' -TestCases @(
        @{ Case = 'Ordner → Nur bestimmte Ordner'; Json = '{"FileScan":{"Paths":["%USERPROFILE%"],"Drives":[]}}'; Expected = 'Folders' }
        @{ Case = 'nur Laufwerke → Ganze Laufwerke'; Json = '{"FileScan":{"Paths":[],"Drives":["C:"]}}'; Expected = 'Drives' }
        @{ Case = 'beides → Ordner (schneller)'; Json = '{"FileScan":{"Paths":["D:\\Tools"],"Drives":["C:"]}}'; Expected = 'Folders' }
        @{ Case = 'nichts → keine Option'; Json = '{"FileScan":{"Paths":[],"Drives":[]}}'; Expected = $null }
    ) {
        $Json | Set-Content $settingsFile
        (Get-InventorySetting).FileScan.Mode | Should -Be $Expected
    }

    It 'behält eine bewusst leere Option und ignoriert ungültige Werte' {
        '{"FileScan":{"Mode":null,"Paths":["%USERPROFILE%"]}}' | Set-Content $settingsFile
        (Get-InventorySetting).FileScan.Mode | Should -BeNullOrEmpty
        '{"FileScan":{"Mode":"Alles","Paths":["%USERPROFILE%"]}}' | Set-Content $settingsFile
        (Get-InventorySetting).FileScan.Mode | Should -BeNullOrEmpty
    }

    It 'die übernommene alte Einstellung %USERPROFILE% wird als „Nur bestimmte Ordner“ gespeichert' {
        '{"FileScan":{"Paths":["%USERPROFILE%"],"Drives":[]}}' | Set-Content $settingsFile
        Set-InventorySetting -PortableSearch $true | Out-Null
        (Get-Content $settingsFile -Raw | ConvertFrom-Json).FileScan.Mode | Should -Be 'Folders'
    }

    It 'Vorlage <Preset> setzt Option und nur deren Liste, die andere bleibt' -TestCases @(
        @{ Preset = 'Quick'; Mode = 'Folders'; Paths = @('%USERPROFILE%'); Drives = @('F:') }
        @{ Preset = 'Thorough'; Mode = 'Drives'; Paths = @('D:\Eigen'); Drives = @('C:') }
    ) {
        Set-InventorySetting -ScanPath 'D:\Eigen' -ScanDrive F | Out-Null
        $s = Set-InventorySetting -Preset $Preset
        $s.FileScan.Mode | Should -Be $Mode
        $s.FileScan.Paths | Should -Be $Paths
        $s.FileScan.Drives | Should -Be $Drives
        $s.PortableSearch.Enabled | Should -BeFalse
    }
}
