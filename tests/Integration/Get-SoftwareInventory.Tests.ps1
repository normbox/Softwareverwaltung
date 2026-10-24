BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

# Läuft gegen das echte System; prüft nur Struktur und Plausibilität.
Describe 'Get-SoftwareInventory (echtes System)' -Tag Integration {
    BeforeAll {
        $inventory = @(Get-SoftwareInventory -WarningAction SilentlyContinue)
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

    It 'speichert und lädt einen Snapshot verlustfrei' {
        $file = $inventory | Save-InventorySnapshot -Directory (Join-Path $TestDrive 'scans')
        $loaded = Get-InventorySnapshot -LiteralPath $file.FullName
        $loaded.Count | Should -Be $inventory.Count
        Compare-InventorySnapshot -Reference $inventory -Difference $loaded | Should -BeNullOrEmpty
    }
}
