BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

# Läuft gegen das echte Inventar, aber ohne externe Dienste (alle aus).
Describe 'Test-SoftwareUpdate (echtes System, ohne externe Dienste)' -Tag Integration {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { InModuleScope SoftwareInventory { New-DefaultSetting } }
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw 'Ohne Freigabe darf keine Anfrage hinausgehen' }
        Mock -ModuleName SoftwareInventory Find-WingetCandidate { throw 'Ohne Freigabe darf keine winget-Suche laufen' }
        $inventory = @(Get-SoftwareInventory -Source RegistryMachine, RegistryUser, Winget, Appx -WarningAction SilentlyContinue)
        $result = @($inventory | Test-SoftwareUpdate -WarningAction SilentlyContinue)
    }

    It 'liefert einen Status für jedes Programm' {
        $result.Count | Should -Be $inventory.Count
        $result.Status | ForEach-Object { $_ | Should -BeIn 'UpToDate', 'Outdated', 'Unknown' }
    }

    It 'nennt für jedes Unknown einen Grund' {
        $result | Where-Object Status -eq 'Unknown' | ForEach-Object { $_.Reason | Should -Not -BeNullOrEmpty -Because $_.Name }
    }

    It 'meldet Updates nur, wenn die neueste Version wirklich neuer ist' {
        $result | Where-Object Status -eq 'Outdated' | ForEach-Object {
            Compare-SoftwareVersion $_.InstalledVersion $_.LatestVersion | Should -Be -1 -Because $_.Name
        }
    }

    It 'schickt ohne Freigabe nichts ins Internet' {
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 0 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Find-WingetCandidate -Times 0 -Exactly
    }
}
