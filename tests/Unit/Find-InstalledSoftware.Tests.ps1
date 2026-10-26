BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([string] $Name, [hashtable] $Property)
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; P = $Property } { New-SoftwareRecord -Name $N -Source Registry -Property $P }
    }
}

Describe 'Find-InstalledSoftware' {
    BeforeEach {
        $script:Inventory = @(
            New-TestRecord 'Contoso Tool 3.0' @{ RegistryKey = 'HKLM:\X\{NEW}'; WingetId = 'Contoso.Tool'; Version = '3.0' }
            New-TestRecord 'Other' @{ RegistryKey = 'HKLM:\X\Other'; Version = '1.0' }
            New-TestRecord 'Store App' @{ PackageFamilyName = 'Contoso.App_abc'; Version = '2.0' }
        )
        Mock -ModuleName SoftwareInventory Get-SoftwareInventory { $script:Inventory }
    }

    It 'findet ein Programm nach einem MSI-Update mit neuem Registry-Schlüssel über die winget-ID' {
        $old = New-TestRecord 'Contoso Tool 2.1' @{ RegistryKey = 'HKLM:\X\{OLD}'; WingetId = 'contoso.tool'; Version = '2.1' }
        $found = Find-InstalledSoftware -Reference $old
        $found.Name | Should -Be 'Contoso Tool 3.0'
    }

    It 'akzeptiert Objekte mit .Record und findet Store-Apps über den PackageFamilyName' {
        $rating = [pscustomobject] @{ Name = 'Store App'; Record = (New-TestRecord 'Store App' @{ PackageFamilyName = 'Contoso.App_abc' }) }
        ($rating | Find-InstalledSoftware).Name | Should -Be 'Store App'
    }

    It 'liefert nichts, wenn das Programm nicht mehr installiert ist' {
        $gone = New-TestRecord 'Weg' @{ RegistryKey = 'HKLM:\X\Weg' }
        Find-InstalledSoftware -Reference $gone | Should -BeNullOrEmpty
    }

    It 'ordnet nie allein über den Namen zu' {
        $nameOnly = New-TestRecord 'Other' @{}
        Find-InstalledSoftware -Reference $nameOnly | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Get-SoftwareInventory -Times 0
    }
}
