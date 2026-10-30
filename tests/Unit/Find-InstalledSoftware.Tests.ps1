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

Describe 'Find-InstalledSoftware bei portablen Programmen' {
    BeforeAll {
        function New-PortableRecord {
            param([string] $Path, [string[]] $Flags = @())
            InModuleScope SoftwareInventory -Parameters @{ F = $Path; G = $Flags } {
                New-SoftwareRecord -Name 'PSPad editor' -Source Portable -Property @{
                    Version = '0.1'; InstallType = 'Portable'; FilePath = $F; InstallLocation = (Split-Path $F)
                    Evidence = [string[]] @('UserAssist'); RunCount = 12; Flags = [string[]] $G
                }
            }
        }
    }
    BeforeEach {
        Mock -ModuleName SoftwareInventory Get-SoftwareInventory { throw 'Das Inventar darf für portable Programme nicht gelesen werden' }
        # Echte .exe als Prüfling (eine kleine Windows-Datei), ohne sie auszuführen
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        $script:Exe = Join-Path $dir 'PSPad.exe'
        Copy-Item -LiteralPath (Join-Path $env:windir 'System32\whoami.exe') -Destination $script:Exe
    }

    It 'liest die Datei neu und behält Nutzungsspuren und den Hinweis auf mehrere Versionen' {
        $found = Find-InstalledSoftware -Reference (New-PortableRecord $script:Exe -Flags 'MultipleVersions')
        @($found).Count | Should -Be 1
        $found.FilePath | Should -Be $script:Exe
        $found.Sources | Should -Contain 'Portable'
        $found.Version | Should -Not -Be '0.1'   # aus der Datei, nicht aus dem alten Datensatz
        $found.Evidence | Should -Be @('UserAssist')
        $found.RunCount | Should -Be 12
        $found.Flags | Should -Contain 'MultipleVersions'
        $found.PSObject.Properties['CopyKey'] | Should -BeNullOrEmpty
    }

    It 'liefert nichts, wenn die Datei fehlt' {
        Remove-Item -LiteralPath $script:Exe
        Find-InstalledSoftware -Reference (New-PortableRecord $script:Exe) | Should -BeNullOrEmpty
    }

    It 'liefert den bisherigen Datensatz, wenn das Laufwerk nicht verbunden ist' {
        $reference = New-PortableRecord 'Q:\Tools\PSPad\PSPad.exe'
        Mock -ModuleName SoftwareInventory Test-PathRootReachable { $false }
        $found = Find-InstalledSoftware -Reference $reference
        $found.FilePath | Should -Be 'Q:\Tools\PSPad\PSPad.exe'
        $found.Version | Should -Be '0.1'
    }
}
