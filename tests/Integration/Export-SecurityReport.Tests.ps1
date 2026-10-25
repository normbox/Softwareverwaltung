BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

# Echtes Inventar, ohne externe Dienste: nichts darf Grün werden, jedes Grau hat einen Grund.
Describe 'Ampel und Bericht (echtes System, ohne externe Dienste)' -Tag Integration {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { InModuleScope SoftwareInventory { New-DefaultSetting } }
        Mock -ModuleName SoftwareInventory Get-CpeMappingPath { Join-Path $TestDrive 'cpe-map.json' }
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw 'Ohne Freigabe darf keine Anfrage hinausgehen' }
        $inventory = @(Get-SoftwareInventory -Source RegistryMachine, RegistryUser, Winget, Appx -WarningAction SilentlyContinue)
        $ratings = @($inventory | Get-SecurityRating -WarningAction SilentlyContinue)
        $file = $ratings | Export-SecurityReport -Path (Join-Path $TestDrive 'bericht.html')
        $html = Get-Content $file.FullName -Raw
    }

    It 'bewertet jedes Programm' {
        $ratings.Count | Should -Be $inventory.Count
    }

    It 'meldet ohne Sicherheitsprüfung nichts als Grün' {
        $ratings | Where-Object Rating -eq 'Green' | Should -BeNullOrEmpty
    }

    It 'nennt für jedes Grau einen Grund' {
        $ratings | Where-Object Rating -eq 'Gray' | ForEach-Object { $_.Reasons | Should -Not -BeNullOrEmpty -Because $_.Name }
    }

    It 'schreibt den Bericht ohne Benutzer- und Rechnernamen' {
        $html | Should -Match "<tr class='row'"
        $html | Should -Not -Match ([regex]::Escape($env:USERPROFILE))
        $html | Should -Not -Match "\b$([regex]::Escape($env:COMPUTERNAME))\b"
    }

    It 'schickt ohne Freigabe nichts ins Internet' {
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 0 -Exactly
    }
}
