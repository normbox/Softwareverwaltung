BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'winget-Manifest: UpgradeBehavior' {
    It 'bildet die Adresse aus ID und Version: <Id>' -TestCases @(
        @{ Id = 'ElectronicArts.EADesktop'; Version = '13.822.0.6335'; Expected = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/e/ElectronicArts/EADesktop/13.822.0.6335/ElectronicArts.EADesktop.installer.yaml' }
        @{ Id = 'Microsoft.VisualStudio.2022.Community'; Version = '17.14.44'; Expected = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests/m/Microsoft/VisualStudio/2022/Community/17.14.44/Microsoft.VisualStudio.2022.Community.installer.yaml' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ I = $Id; V = $Version } { Get-WingetManifestUri -Id $I -Version $V } | Should -Be $Expected
    }

    It 'erkennt das Feld: <Case>' -TestCases @(
        @{ Case = 'oben'; Yaml = "PackageIdentifier: A.B`r`nUpgradeBehavior: uninstallPrevious`r`nInstallers:`r`n- Architecture: x64"; Expected = $true }
        @{ Case = 'je Eintrag'; Yaml = "Installers:`n- Architecture: x64`n  UpgradeBehavior: uninstallPrevious`n- Architecture: x86"; Expected = $true }
        @{ Case = 'als erstes Feld des Eintrags'; Yaml = "Installers:`n- UpgradeBehavior: 'uninstallPrevious'`n  Architecture: x64"; Expected = $true }
        @{ Case = 'mit Kommentar'; Yaml = "UpgradeBehavior: uninstallPrevious # wegen Dienst"; Expected = $true }
        @{ Case = 'anderer Wert'; Yaml = "UpgradeBehavior: install"; Expected = $false }
        @{ Case = 'kein Feld'; Yaml = "PackageIdentifier: A.B"; Expected = $false }
        @{ Case = 'nur auskommentiert'; Yaml = "# UpgradeBehavior: uninstallPrevious"; Expected = $false }
    ) {
        $json = InModuleScope SoftwareInventory -Parameters @{ Y = $Yaml } { ConvertTo-WingetManifestCacheContent $Y }
        ($json | ConvertFrom-Json).UninstallsPrevious | Should -Be $Expected
    }

    Context 'Test-WingetUninstallsPrevious' {
        BeforeEach {
            InModuleScope SoftwareInventory {
                $script:testRecord = New-SoftwareRecord -Name 'Contoso' -Source Winget -Property @{ WingetId = 'Contoso.Tool'; WingetSource = 'winget'; AvailableVersion = '2.0' }
                $script:on = [pscustomobject] @{ Services = [pscustomobject] @{ WingetManifest = $true } }
                $script:off = [pscustomobject] @{ Services = [pscustomobject] @{ WingetManifest = $false } }
                Mock Get-SoftwareCatalog { @() }
                Mock Invoke-ServiceRequest { [pscustomobject] @{ UninstallsPrevious = $true } }
            }
        }

        It 'fragt bei eingeschaltetem Dienst mit kurzer Zeitgrenze und ohne Warten nach' {
            InModuleScope SoftwareInventory {
                Test-WingetUninstallsPrevious -Record $script:testRecord -Id 'Contoso.Tool' -Source 'winget' -Setting $script:on | Should -BeTrue
                Should -Invoke Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { $Service -eq 'WingetManifest' -and $TimeoutSeconds -eq 5 -and $NoRetryWait -and $CacheKey -eq 'Contoso.Tool/2.0' }
            }
        }

        It 'fragt bei ausgeschaltetem Dienst nichts ab' {
            InModuleScope SoftwareInventory {
                Test-WingetUninstallsPrevious -Record $script:testRecord -Id 'Contoso.Tool' -Source 'winget' -Setting $script:off | Should -BeFalse
                Should -Invoke Invoke-ServiceRequest -Times 0
            }
        }

        It 'fragt für die Quelle msstore nicht nach' {
            InModuleScope SoftwareInventory {
                Test-WingetUninstallsPrevious -Record $script:testRecord -Id 'Contoso.Tool' -Source 'msstore' -Setting $script:on | Should -BeFalse
                Should -Invoke Invoke-ServiceRequest -Times 0
            }
        }

        It 'fragt ohne Zielversion nicht nach' {
            InModuleScope SoftwareInventory {
                $record = New-SoftwareRecord -Name 'Contoso' -Source Winget -Property @{ WingetId = 'Contoso.Tool'; WingetSource = 'winget' }
                Test-WingetUninstallsPrevious -Record $record -Id 'Contoso.Tool' -Source 'winget' -Setting $script:on | Should -BeFalse
                Should -Invoke Invoke-ServiceRequest -Times 0
            }
        }

        It 'warnt nicht und blockiert nicht, wenn der Abruf scheitert' {
            InModuleScope SoftwareInventory {
                Mock Invoke-ServiceRequest { throw 'nicht erreichbar' }
                Test-WingetUninstallsPrevious -Record $script:testRecord -Id 'Contoso.Tool' -Source 'winget' -Setting $script:on | Should -BeFalse
            }
        }
    }

    It 'speichert über Invoke-ServiceRequest nur das Feld' {
        InModuleScope SoftwareInventory {
            Mock Get-CacheDirectory { Join-Path $TestDrive 'cache' }
            Mock Invoke-WebRequest { [pscustomobject] @{ Content = "UpgradeBehavior: uninstallPrevious`nInstallerSha256: ABC" } }
            $setting = [pscustomobject] @{ Services = [pscustomobject] @{ WingetManifest = $true } }
            $uri = Get-WingetManifestUri -Id 'A.B' -Version '1.0'
            (Invoke-ServiceRequest -Service WingetManifest -Uri $uri -CacheKey 'A.B/1.0' -MaxAge ([timespan]::FromDays(30)) -TimeoutSeconds 5 -Setting $setting).UninstallsPrevious | Should -BeTrue
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $TimeoutSec -eq 5 }
            $file = Get-ChildItem (Join-Path $TestDrive 'cache\WingetManifest') -File
            Get-Content -LiteralPath $file.FullName -Raw | Should -Not -Match 'ABC'
            # Zweiter Aufruf kommt aus dem Zwischenspeicher
            (Invoke-ServiceRequest -Service WingetManifest -Uri $uri -CacheKey 'A.B/1.0' -MaxAge ([timespan]::FromDays(30)) -TimeoutSeconds 5 -Setting $setting).UninstallsPrevious | Should -BeTrue
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
        }
    }
}

Describe 'Katalogfeld VendorUpdateUrl' {
    It 'lehnt Adressen ohne https ab' {
        $entry = '{"Id":"x","Name":"X","Match":{"WingetId":["X.X"]},"VendorUpdateUrl":"http://example.org/"}' | ConvertFrom-Json
        InModuleScope SoftwareInventory -Parameters @{ E = $entry } { Test-CatalogEntry -Entry $E -FileName 'x' } | Should -BeLike '*https://*'
    }
}
