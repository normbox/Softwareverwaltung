BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'ConvertTo-NormalizedVersion' {
    It 'normalisiert <Raw> zu <Expected>' -TestCases @(
        @{ Raw = '24.08'; Expected = '24.8' }
        @{ Raw = '24.8.0.0'; Expected = '24.8' }
        @{ Raw = 'v8.9.8.1'; Expected = '8.9.8.1' }
        @{ Raw = 'Version 3.0'; Expected = '3' }
        @{ Raw = '7-Zip 26.05'; Expected = $null }
        @{ Raw = '1.2.3 (x64)'; Expected = '1.2.3' }
        @{ Raw = '2.0.1+build.77'; Expected = '2.0.1' }
        @{ Raw = '1.4.2-g1a2b3c4'; Expected = '1.4.2' }
        @{ Raw = '1.4.2 1a2b3c4d5e'; Expected = '1.4.2' }
        @{ Raw = '1.4.2 Build 7'; Expected = $null }
        @{ Raw = '1.0-beta2'; Expected = '1-beta2' }
        @{ Raw = '3.14.0rc1'; Expected = '3.14-rc1' }
        @{ Raw = '1.1.1w'; Expected = '1.1.1w' }
        @{ Raw = '0.0'; Expected = '0' }
        @{ Raw = '< 2026.3.1'; Expected = $null }
        @{ Raw = 'Unknown'; Expected = $null }
        @{ Raw = ''; Expected = $null }
    ) {
        $v = InModuleScope SoftwareInventory -Parameters @{ R = $Raw } { ConvertTo-NormalizedVersion $R }
        if ($null -eq $Expected) { $v | Should -BeNullOrEmpty } else { $v.Normalized | Should -Be $Expected }
    }

    It 'behält die Originalangabe' {
        (InModuleScope SoftwareInventory { ConvertTo-NormalizedVersion ' v1.2 ' }).Raw | Should -Be ' v1.2 '
    }
}

Describe 'Compare-SoftwareVersion' {
    It '<A> gegen <B> ergibt <Expected>' -TestCases @(
        @{ A = '24.08'; B = '24.8.0.0'; Expected = 0 }
        @{ A = '24.08'; B = '24.09'; Expected = -1 }
        @{ A = '24.10'; B = '24.9'; Expected = 1 }
        @{ A = '1.10'; B = '1.9.99'; Expected = 1 }
        @{ A = 'v8.9.8.1'; B = '8.9.8.1'; Expected = 0 }
        @{ A = '3.13.15150.1013'; B = '3.13.15150.0'; Expected = 1 }
        @{ A = '1.0-beta'; B = '1.0'; Expected = -1 }
        @{ A = '1.0-alpha'; B = '1.0-beta'; Expected = -1 }
        @{ A = '1.0-rc2'; B = '1.0-rc10'; Expected = -1 }
        @{ A = '1.0-rc1'; B = '0.9'; Expected = 1 }
        @{ A = '1.1.1w'; B = '1.1.1'; Expected = 1 }
        @{ A = '1.1.1v'; B = '1.1.1w'; Expected = -1 }
        @{ A = '1.2.3 (x64)'; B = '1.2.3'; Expected = 0 }
        @{ A = '2026.1024.1343.44'; B = '2026.1024.1343.45'; Expected = -1 }
    ) {
        Compare-SoftwareVersion $A $B | Should -Be $Expected
        # Spiegelbildlich
        Compare-SoftwareVersion $B $A | Should -Be (-1 * $Expected)
    }

    It 'meldet unbekannt statt gleich, wenn eine Seite nicht lesbar ist: <A> / <B>' -TestCases @(
        @{ A = 'Unknown'; B = '1.0' }
        @{ A = '1.0'; B = '< 2.0' }
        @{ A = ''; B = '' }
        @{ A = $null; B = '1.0' }
    ) {
        Compare-SoftwareVersion $A $B | Should -BeNullOrEmpty
    }
}
