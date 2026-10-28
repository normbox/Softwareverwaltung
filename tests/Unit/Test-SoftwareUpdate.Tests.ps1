BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([string] $Name, [string] $Version, [string] $Publisher = 'Contoso', [string] $WingetId, [string] $AvailableVersion)
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; V = $Version; P = $Publisher; W = $WingetId; A = $AvailableVersion } {
            New-SoftwareRecord -Name $N -Source Registry -Property @{ Version = $V; Publisher = $P; WingetId = $W; AvailableVersion = $A }
        }
    }

    function Use-Setting {
        # Mockt die Einstellungen mit den angegebenen aktivierten Diensten.
        param([string[]] $Service = @())
        $script:TestServices = $Service
        Mock -ModuleName SoftwareInventory Read-InventorySetting {
            $s = InModuleScope SoftwareInventory { New-DefaultSetting }
            foreach ($name in $script:TestServices) { $s.Services.$name = $true }
            $s
        }
    }

    function Use-Catalog {
        param([string[]] $Json)
        $script:TestCatalog = @($Json | ForEach-Object { $_ | ConvertFrom-Json })
        Mock -ModuleName SoftwareInventory Get-SoftwareCatalog { $script:TestCatalog }
    }

    function Get-ReasonCode {
        # Codes einer Meldung samt verschachtelter Meldungen in den Args (z. B. NoLatestVersion).
        param($Message)
        foreach ($m in @($Message)) {
            if ($null -eq $m -or -not $m.PSObject.Properties['Code']) { continue }
            $m.Code
            foreach ($a in @($m.Args)) { Get-ReasonCode $a }
        }
    }

    $contosoCatalog = '{"Id":"contoso","Name":"Contoso","Match":{"NamePattern":"^Contoso Tool","Publisher":["Contoso"]},"GitHub":{"Repository":"contoso/tool"}}'
}

Describe 'Test-SoftwareUpdate' {
    BeforeEach {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw 'Es darf keine echte Anfrage hinausgehen' }
    }

    It 'nutzt winget: Update verfügbar' {
        Use-Setting; Use-Catalog @()
        $r = New-TestRecord 'Audacity 3.7.7' '3.7.7' -WingetId 'Audacity.Audacity' -AvailableVersion '4.0.1.262721353' | Test-SoftwareUpdate
        $r.Status | Should -Be 'Outdated'
        $r.LatestVersion | Should -Be '4.0.1.262721353'
        $r.Source | Should -Be 'Winget'
        $r.Confirmed | Should -BeTrue
    }

    It 'meldet eigenen Fortschritt mit Zähler und Programmname' {
        Use-Setting; Use-Catalog @()
        Mock -ModuleName SoftwareInventory Write-Progress { }
        $records = @(
            New-TestRecord 'Alpha' '1.0' -WingetId 'A.A'
            New-TestRecord 'Beta' '2.0' -WingetId 'B.B'
        )
        Test-SoftwareUpdate -InputObject $records | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Write-Progress -ParameterFilter { $Activity -eq 'Prüfe neueste Versionen (2 von 2)' -and $Status -eq 'Beta' } -Times 1 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Write-Progress -ParameterFilter { $Completed } -Times 1 -Exactly
    }

    It 'nutzt winget: kein Update gemeldet heißt aktuell' {
        Use-Setting; Use-Catalog @()
        $r = New-TestRecord '7-Zip' '26.05' -WingetId '7zip.7zip' | Test-SoftwareUpdate
        $r.Status | Should -Be 'UpToDate'
        $r.LatestVersion | Should -Be '26.05'
    }

    It 'fragt GitHub nur bei aktiviertem Dienst und meldet sonst den Grund' {
        Use-Setting; Use-Catalog $contosoCatalog
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { throw 'darf nicht aufgerufen werden' }
        $r = New-TestRecord 'Contoso Tool' '1.0' | Test-SoftwareUpdate
        $r.Status | Should -Be 'Unknown'
        Get-ReasonCode $r.Reason | Should -Contain 'ServiceDisabled'
        $r.Reason.Text | Should -Match 'Dienst GitHub nicht aktiviert'
        $r.CatalogId | Should -Be 'contoso'
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly
    }

    It 'liest die neueste Version aus GitHub-Releases' {
        Use-Setting GitHub; Use-Catalog $contosoCatalog
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ tag_name = 'v1.4.0' } }
        $r = New-TestRecord 'Contoso Tool' '1.2' | Test-SoftwareUpdate
        $r.Status | Should -Be 'Outdated'
        $r.LatestVersion | Should -Be '1.4.0'
        $r.Source | Should -Be 'GitHub'
        $r.Confirmed | Should -BeTrue
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter {
            $Service -eq 'GitHub' -and "$Uri" -eq 'https://api.github.com/repos/contoso/tool/releases/latest' -and $CacheKey
        }
    }

    It 'wendet das TagPattern des Katalogs an' {
        Use-Setting GitHub
        Use-Catalog '{"Id":"audacity","Name":"Audacity","Match":{"NamePattern":"^Audacity","Publisher":["Audacity Team"]},"GitHub":{"Repository":"audacity/audacity","TagPattern":"^Audacity-(?<version>\\d.*)$"}}'
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ tag_name = 'Audacity-4.0.1' } }
        $r = New-TestRecord 'Audacity' '4.0.1' -Publisher 'Audacity Team' | Test-SoftwareUpdate
        $r.LatestVersion | Should -Be '4.0.1'
        $r.Status | Should -Be 'UpToDate'
    }

    It 'hält winget vor GitHub (erster Treffer gewinnt)' {
        Use-Setting GitHub
        Use-Catalog '{"Id":"contoso","Name":"Contoso","Match":{"WingetId":["Contoso.Tool"]},"GitHub":{"Repository":"contoso/tool"}}'
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { throw 'darf nicht aufgerufen werden' }
        $r = New-TestRecord 'Contoso Tool' '1.0' -WingetId 'Contoso.Tool' -AvailableVersion '2.0' | Test-SoftwareUpdate
        $r.Source | Should -Be 'Winget'
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly
    }

    It 'stoppt GitHub-Abfragen nach erreichtem Anfragelimit' {
        Use-Setting GitHub; Use-Catalog $contosoCatalog
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            $e = [System.Exception]::new('GitHub-Anfragelimit erreicht (HTTP 403).'); $e.Data['Reason'] = 'RateLimit'; throw $e
        }
        $records = @(New-TestRecord 'Contoso Tool' '1.0'; New-TestRecord 'Contoso Tool Pro' '1.0')
        $r = @($records | Test-SoftwareUpdate -WarningAction SilentlyContinue)
        $r | ForEach-Object { $_.Status | Should -Be 'Unknown'; Get-ReasonCode $_.Reason | Should -Contain 'RateLimit' }
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly
    }

    It 'meldet ein unpassendes Release-Tag als Grund' {
        Use-Setting GitHub; Use-Catalog $contosoCatalog
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ tag_name = 'nightly-build' } }
        Get-ReasonCode (New-TestRecord 'Contoso Tool' '1.0' | Test-SoftwareUpdate).Reason | Should -Contain 'GitHubTagMismatch'
    }

    Context 'winget-Suche' {
        BeforeEach {
            Use-Setting WingetSearch; Use-Catalog @()
            Mock -ModuleName SoftwareInventory Get-Command { $true } -ParameterFilter { $Name -eq 'Find-WinGetPackage' }
            Mock -ModuleName SoftwareInventory Get-WingetExecutable { 'C:\Program Files\WindowsApps\x\winget.exe' }
            $script:Publishers = @{ 'JanFiala.PSPad.x64' = 'Jan Fiala'; 'JanFiala.PSPad.x86' = 'Jan Fiala'; 'Fake.PSPad' = 'Mallory' }
            Mock -ModuleName SoftwareInventory Get-WingetPackagePublisher { $script:Publishers[$Id] }
            $script:CacheDir = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
            Mock -ModuleName SoftwareInventory Get-CacheDirectory { $script:CacheDir }
        }

        It 'lässt Store-Apps aus' {
            Mock -ModuleName SoftwareInventory Find-WingetCandidate { throw 'darf nicht aufgerufen werden' }
            $r = InModuleScope SoftwareInventory {
                New-SoftwareRecord -Name 'Gaming Services' -Source Appx -Property @{ Version = '38.118.9001.0'; Publisher = 'Microsoft Corporation'; InstallType = 'MSIX' }
            } | Test-SoftwareUpdate
            $r.Status | Should -Be 'Unknown'
            Get-ReasonCode $r.Reason | Should -Contain 'StoreApp'
        }

        It 'verwirft unplausible Treffer: <Case>' -TestCases @(
            @{ Case = 'viel neuere Hauptversion'; Installed = '1.0'; Found = '154.0.8037.40' }
            @{ Case = 'kleinere Hauptversion'; Installed = '3.5.0.0'; Found = '2.9' }
        ) {
            $script:Found = $Found
            $script:Publishers = @{ 'Google.Tool' = 'Google LLC' }
            Mock -ModuleName SoftwareInventory Find-WingetCandidate { [pscustomobject] @{ Name = 'Tool'; Id = 'Google.Tool'; Version = $script:Found } }
            $r = New-TestRecord 'Tool' $Installed -Publisher 'Google LLC' | Test-SoftwareUpdate
            $r.Status | Should -Be 'Unknown'
            Get-ReasonCode $r.Reason | Should -Contain 'WingetSearchImplausible'
        }

        It 'akzeptiert eine Hauptversion Abstand nach oben' {
            $script:Publishers = @{ 'Oven.Bun' = 'Oven' }
            Mock -ModuleName SoftwareInventory Find-WingetCandidate { [pscustomobject] @{ Name = 'Bun'; Id = 'Oven.Bun'; Version = '2.0.1' } }
            (New-TestRecord 'Bun' '1.3.3.0' -Publisher 'Oven' | Test-SoftwareUpdate).Status | Should -Be 'Outdated'
        }

        It 'speichert Suchergebnisse zwischen' {
            Mock -ModuleName SoftwareInventory Find-WingetCandidate { [pscustomobject] @{ Name = 'PSPad editor (x64)'; Id = 'JanFiala.PSPad.x64'; Version = '5.5.2.851' } }
            $first = New-TestRecord 'PSPad' '5.0.0.0' -Publisher 'Jan Fiala' | Test-SoftwareUpdate
            $second = New-TestRecord 'PSPad' '5.0.0.0' -Publisher 'Jan Fiala' | Test-SoftwareUpdate
            $second.LatestVersion | Should -Be $first.LatestVersion
            Should -Invoke -ModuleName SoftwareInventory Find-WingetCandidate -Times 1 -Exactly
            Should -Invoke -ModuleName SoftwareInventory Get-WingetPackagePublisher -Times 1 -Exactly
        }

        It 'findet Programme ohne winget-ID über Name und Hersteller, Ergebnis unbestätigt' {
            Mock -ModuleName SoftwareInventory Find-WingetCandidate {
                [pscustomobject] @{ Name = 'PSPad editor (x64)'; Id = 'JanFiala.PSPad.x64'; Version = '5.5.2.851' }
                [pscustomobject] @{ Name = 'PSPad editor (x86)'; Id = 'JanFiala.PSPad.x86'; Version = '5.5.2.851' }
                [pscustomobject] @{ Name = 'PSPad'; Id = 'Fake.PSPad'; Version = '9.9' }
            }
            $r = New-TestRecord 'PSPad' '5.0.0.0' -Publisher 'Jan Fiala' | Test-SoftwareUpdate
            $r.Status | Should -Be 'Outdated'
            $r.LatestVersion | Should -Be '5.5.2.851'
            $r.Source | Should -Be 'WingetSearch'
            $r.Confirmed | Should -BeFalse
        }

        It 'verwendet keine Treffer mit verschiedenen Versionen' {
            $script:Publishers = @{ 'A.Tool' = 'Contoso'; 'B.Tool' = 'Contoso Ltd' }
            Mock -ModuleName SoftwareInventory Find-WingetCandidate {
                [pscustomobject] @{ Name = 'Tool'; Id = 'A.Tool'; Version = '2.0' }
                [pscustomobject] @{ Name = 'Tool Pro'; Id = 'B.Tool'; Version = '3.0' }
            }
            $r = New-TestRecord 'Tool' '1.0' | Test-SoftwareUpdate
            $r.Status | Should -Be 'Unknown'
            Get-ReasonCode $r.Reason | Should -Contain 'WingetSearchAmbiguous'
        }

        It 'fragt bei zu vielen Namenstreffern keine Hersteller ab' {
            Mock -ModuleName SoftwareInventory Find-WingetCandidate {
                1..6 | ForEach-Object { [pscustomobject] @{ Name = "Python 3.$_"; Id = "Python.Python.3.$_"; Version = "3.$_.0" } }
            }
            $r = New-TestRecord 'Python' '3.11' -Publisher 'Python Software Foundation' | Test-SoftwareUpdate
            Get-ReasonCode $r.Reason | Should -Contain 'WingetSearchAmbiguousCount'
            $r.Reason.Text | Should -Match 'mehrdeutig \(6 Pakete'
            Should -Invoke -ModuleName SoftwareInventory Get-WingetPackagePublisher -Times 0 -Exactly
        }

        It 'ordnet ähnliche, aber andere Namen nicht zu' {
            Mock -ModuleName SoftwareInventory Find-WingetCandidate { [pscustomobject] @{ Name = 'PSPadX'; Id = 'JanFiala.PSPad.x64'; Version = '1.0' } }
            (New-TestRecord 'PSPad' '5.0' -Publisher 'Jan Fiala' | Test-SoftwareUpdate).Reason | ForEach-Object { Get-ReasonCode $_ } | Should -Contain 'WingetSearchNoMatch'
        }
    }

    It 'nennt einen Grund, wenn gar keine Quelle bekannt ist' {
        Use-Setting; Use-Catalog @()
        $r = New-TestRecord 'Unbekannt' '1.0' | Test-SoftwareUpdate
        $r.Status | Should -Be 'Unknown'
        Get-ReasonCode $r.Reason | Should -Contain 'ServiceDisabled'
        $r.Reason.Text | Should -Match 'WingetSearch nicht aktiviert'
    }

    It 'meldet unlesbare installierte Versionen als unbekannt statt aktuell' {
        Use-Setting; Use-Catalog @()
        $r = New-TestRecord 'Battle.net' 'Unknown' -WingetId 'Blizzard.BattleNet' | Test-SoftwareUpdate
        $r.Status | Should -Be 'Unknown'
        $r.Reason.Code | Should -Be 'InstalledVersionUnreadable'
        $r.Reason.Args | Should -Be @('Unknown')
    }

    It 'verarbeitet eine Liste von Datensätzen über die Pipeline' {
        Use-Setting; Use-Catalog @()
        $r = @(@(
                New-TestRecord 'A' '1.0' -WingetId 'A.A' -AvailableVersion '1.1'
                New-TestRecord 'B' '2.0' -WingetId 'B.B'
            ) | Test-SoftwareUpdate)
        $r.Count | Should -Be 2
        $r.Status | Should -Be @('Outdated', 'UpToDate')
        $r[0].Record.Name | Should -Be 'A'
    }
}
