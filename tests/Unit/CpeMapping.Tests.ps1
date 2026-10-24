BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRecord {
        param([string] $Name = 'GIMP 3.2.4', [string] $Version = '3.2.4.0', [string] $Publisher = 'The GIMP Team', [string] $WingetId)
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; V = $Version; P = $Publisher; W = $WingetId } {
            New-SoftwareRecord -Name $N -Source Registry -Property @{ Version = $V; Publisher = $P; WingetId = $W }
        }
    }
}

Describe 'CPE-Zuordnungen des Benutzers' {
    BeforeEach {
        $script:MapFile = Join-Path $TestDrive "cpe-map-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-CpeMappingPath { $script:MapFile }
    }

    It 'bildet den Schlüssel aus winget-ID oder Name ohne Version und Hersteller' {
        InModuleScope SoftwareInventory -Parameters @{ R = (New-TestRecord) } { Get-CpeMappingKey $R } | Should -Be 'name:gimp|the'
        InModuleScope SoftwareInventory -Parameters @{ R = (New-TestRecord -Name 'GIMP 3.4.0') } { Get-CpeMappingKey $R } | Should -Be 'name:gimp|the'
        InModuleScope SoftwareInventory -Parameters @{ R = (New-TestRecord -WingetId 'GIMP.GIMP.3') } { Get-CpeMappingKey $R } | Should -Be 'winget:gimp.gimp.3'
    }

    It 'speichert, liest und entfernt Zuordnungen' {
        $saved = New-TestRecord | Set-CpeMapping -Cpe 'cpe:2.3:a:gimp:gimp'
        $saved.Cpe | Should -Be @('cpe:2.3:a:gimp:gimp')
        @(Get-CpeMapping).Count | Should -Be 1
        (Get-CpeMapping).Name | Should -Be 'GIMP 3.2.4'

        Get-CpeMapping | Remove-CpeMapping
        Get-CpeMapping | Should -BeNullOrEmpty
    }

    It 'lehnt CPEs mit Version oder falscher Form ab' {
        { New-TestRecord | Set-CpeMapping -Cpe 'cpe:2.3:a:gimp:gimp:3.2' } | Should -Throw
        { New-TestRecord | Set-CpeMapping -Cpe 'gimp' } | Should -Throw
    }

    It 'nutzt bestätigte Zuordnungen in Get-SoftwareVulnerability, Katalog hat Vorrang' {
        New-TestRecord | Set-CpeMapping -Cpe 'cpe:2.3:a:gimp:gimp' | Out-Null
        New-TestRecord -Name '7-Zip' -Version '26.05' -Publisher 'Igor Pavlov' -WingetId '7zip.7zip' | Set-CpeMapping -Cpe 'cpe:2.3:a:falsch:falsch' | Out-Null
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.NVD = $true; $s }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ totalResults = 0; resultsPerPage = 0; vulnerabilities = @() } }

        $gimp = New-TestRecord | Get-SoftwareVulnerability
        $gimp.Status | Should -Be 'Checked'
        $gimp.CpeSource | Should -Be 'User'
        $gimp.Cpe | Should -Be @('cpe:2.3:a:gimp:gimp:3.2.4:*:*:*:*:*:*:*')

        $zip = New-TestRecord -Name '7-Zip' -Version '26.05' -Publisher 'Igor Pavlov' -WingetId '7zip.7zip' | Get-SoftwareVulnerability
        $zip.CpeSource | Should -Be 'Catalog'
        $zip.Cpe | Should -Be @('cpe:2.3:a:7-zip:7-zip:26.5:*:*:*:*:*:*:*')
    }
}

Describe 'Find-CpeCandidate' {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.NVD = $true; $s }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            $names = @(1..40 | ForEach-Object { "cpe:2.3:a:gimp:gimp:2.$($_):*:*:*:*:*:*:*" }) +
                @(1..3 | ForEach-Object { "cpe:2.3:a:gimp:gimp_print:5.$($_):*:*:*:*:*:*:*" }) +
                @('cpe:2.3:a:other:image_tool:1.0:*:*:*:*:*:*:*', 'cpe:2.3:o:gimp:gimp_os:1:*:*:*:*:*:*:*')
            [pscustomobject] @{ products = @($names | ForEach-Object { [pscustomobject] @{ cpe = [pscustomobject] @{ cpeName = $_ } } }) }
        }
    }

    It 'sucht ohne Versionsangabe im Namen und schlägt das passendste Produkt zuerst vor' {
        $c = @(New-TestRecord -Publisher 'GIMP Development Team' | Find-CpeCandidate)
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -match 'keywordSearch=GIMP&' }
        $c[0].Cpe | Should -Be 'cpe:2.3:a:gimp:gimp'
        $c[0].Confirmed | Should -BeFalse
        $c.Cpe | Should -Not -Contain 'cpe:2.3:a:other:image_tool'   # passt weder Produkt noch Hersteller
        $c.Cpe | Should -Not -Contain 'cpe:2.3:o:gimp:gimp_os'       # nur Anwendungen
    }

    It 'warnt, wenn NVD nicht aktiviert ist' {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { InModuleScope SoftwareInventory { New-DefaultSetting } }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { $e = [System.Exception]::new('Dienst NVD ist nicht aktiviert.'); $e.Data['Reason'] = 'Disabled'; throw $e }
        $r = New-TestRecord | Find-CpeCandidate -WarningVariable w -WarningAction SilentlyContinue
        $r | Should -BeNullOrEmpty
        "$w" | Should -Match 'nicht aktiviert'
    }
}
