BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

# Läuft gegen das echte System; prüft nur Struktur und Plausibilität.
Describe 'Get-SoftwareInventory (echtes System)' -Tag Integration {
    BeforeAll {
        $inventory = @(Get-SoftwareInventory -Source RegistryMachine, RegistryUser, Winget, Appx -WarningAction SilentlyContinue)
    }

    It 'findet installierte Programme' {
        $inventory.Count | Should -BeGreaterThan 0
    }

    It 'liefert für jeden Datensatz Name und Quelle' {
        $inventory | ForEach-Object {
            $_.Name | Should -Not -BeNullOrEmpty
            $_.Sources | Should -Not -BeNullOrEmpty
            $_.PSObject.Properties.Name | Should -Not -Contain 'MatchKeys'
        }
    }

    It 'enthält keine Doppelungen pro Registry-Schlüssel' {
        $keys = $inventory | Where-Object RegistryKey | ForEach-Object RegistryKey
        ($keys | Select-Object -Unique).Count | Should -Be @($keys).Count
    }

    It 'findet portable Programme im schnellen Scan mit vollständigen Datensätzen' {
        $portable = @(Get-PortableSoftware -Trace UserAssist, Process, Autostart, ScheduledTask -Path $env:USERPROFILE -Inventory $inventory -WarningAction SilentlyContinue)
        $portable | ForEach-Object {
            $_.InstallType | Should -Be 'Portable'
            $_.FilePath | Should -Match '\.exe$'
            $_.Sha256 | Should -BeNullOrEmpty
        }
        # Nichts aus dem Windows-Ordner und nichts aus Ordnern installierter Programme
        $portable.FilePath | Where-Object { $_ -like "$env:windir\*" } | Should -BeNullOrEmpty
        $installedDirs = $inventory | Where-Object InstallLocation | ForEach-Object { $_.InstallLocation.TrimEnd('\') + '\' }
        foreach ($p in $portable) {
            $installedDirs | Where-Object { $p.FilePath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) -and $_.Split('\').Count -gt 3 } |
                Should -BeNullOrEmpty -Because $p.FilePath
        }
    }

    It 'speichert und lädt einen Snapshot verlustfrei' {
        $file = $inventory | Save-InventorySnapshot -Directory (Join-Path $TestDrive 'scans')
        $loaded = Get-InventorySnapshot -LiteralPath $file.FullName
        $loaded.Count | Should -Be $inventory.Count
        Compare-InventorySnapshot -Reference $inventory -Difference $loaded | Should -BeNullOrEmpty
    }
}
