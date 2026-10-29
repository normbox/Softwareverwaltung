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
        # Programm ohne Katalogeintrag
        $uae = @{ Name = 'WinUAE 64-bit 6.0.2'; Version = '6.0.2'; Publisher = 'Arabuusimiehet' }
        New-TestRecord @uae | Set-CpeMapping -Cpe 'cpe:2.3:a:winuae:winuae' | Out-Null
        New-TestRecord -Name '7-Zip' -Version '26.05' -Publisher 'Igor Pavlov' -WingetId '7zip.7zip' | Set-CpeMapping -Cpe 'cpe:2.3:a:falsch:falsch' | Out-Null
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.NVD = $true; $s }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ totalResults = 0; resultsPerPage = 0; vulnerabilities = @() } }

        $user = New-TestRecord @uae | Get-SoftwareVulnerability
        $user.Status | Should -Be 'Checked'
        $user.CpeSource | Should -Be 'User'
        $user.Cpe | Should -Be @('cpe:2.3:a:winuae:winuae:6.0.2:*:*:*:*:*:*:*')

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

    It 'sucht über die winget-ID weiter, wenn der Name nichts Passendes liefert, und nennt den Suchbegriff' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            # $Uri ist [uri]; als Text steht das Leerzeichen unmaskiert
            $names = if ("$Uri" -match 'keywordSearch=Total( |%20)Commander&') { @('cpe:2.3:a:ghisler:total_commander:11.0:*:*:*:*:*:*:*') }
            else { @('cpe:2.3:a:other:commander_tool:1.0:*:*:*:*:*:*:*') }
            [pscustomobject] @{ products = @($names | ForEach-Object { [pscustomobject] @{ cpe = [pscustomobject] @{ cpeName = $_ } } }) }
        }
        $record = New-TestRecord -Name 'Totalcmd 64-bit (Remove or Repair)' -Publisher 'Ghisler Software GmbH' -WingetId 'Ghisler.TotalCommander'
        $c = @($record | Find-CpeCandidate)
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly
        $c[0].Cpe | Should -Be 'cpe:2.3:a:ghisler:total_commander'
        $c[0].Query | Should -Be 'Total Commander'
        $c[0].Url | Should -BeLike 'https://nvd.nist.gov/products/cpe/search/*ghisler*'
    }

    It 'schlägt veraltete CPEs nicht vor' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            [pscustomobject] @{ products = @(
                    [pscustomobject] @{ cpe = [pscustomobject] @{ cpeName = 'cpe:2.3:a:gimp:gimp_old:1:*:*:*:*:*:*:*'; deprecated = $true } }
                    [pscustomobject] @{ cpe = [pscustomobject] @{ cpeName = 'cpe:2.3:a:gimp:gimp:3:*:*:*:*:*:*:*'; deprecated = $false } }) }
        }
        (New-TestRecord | Find-CpeCandidate).Cpe | Should -Be @('cpe:2.3:a:gimp:gimp')
    }
}

Describe 'Suchbegriffe und Bewertung für CPE-Vorschläge' {
    It 'bereinigt <Name> zu <Expected>' -TestCases @(
        @{ Name = 'Wireshark 4.6.6 x64'; Expected = 'Wireshark' }
        @{ Name = 'PuTTY release 0.85 (64-bit)'; Expected = 'PuTTY' }
        @{ Name = 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.30501'; Expected = 'Microsoft Visual C++ 2013 Redistributable' }
        @{ Name = 'Mozilla Thunderbird ESR (x64 de)'; Expected = 'Mozilla Thunderbird ESR' }
        @{ Name = 'Cursor (User)'; Expected = 'Cursor' }
        @{ Name = 'Opera Stable 137.0.6036.63'; Expected = 'Opera' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ N = $Name } { ConvertTo-CpeSearchName $N } | Should -Be $Expected
    }

    It 'leitet aus der winget-ID den Produktnamen ab' {
        InModuleScope SoftwareInventory {
            ConvertFrom-WingetIdToSearchName 'Ghisler.TotalCommander' | Should -Be 'Total Commander'
            ConvertFrom-WingetIdToSearchName 'Microsoft.VisualStudio.2022.Community' | Should -Be 'Visual Studio'
            ConvertFrom-WingetIdToSearchName 'XP9KHM4BK9FZ7Q' | Should -BeNullOrEmpty   # Store-ID
        }
    }

    It 'fragt gleiche Suchbegriffe nur einmal ab' {
        $record = New-TestRecord -Name 'Total Commander 64-bit' -Publisher 'Ghisler' -WingetId 'Ghisler.TotalCommander'
        @(InModuleScope SoftwareInventory -Parameters @{ R = $record } { Get-CpeSearchQuery -Record $R }) | Should -Be @('Total Commander')
    }

    It 'bewertet Produkt und Hersteller, ohne Produktbezug gibt es keinen Vorschlag' {
        InModuleScope SoftwareInventory {
            Get-CpeCandidateScore -Vendor 'gimp' -Product 'gimp' -Query 'GIMP' -Publisher 'The GIMP Team' | Should -Be 5
            Get-CpeCandidateScore -Vendor 'irfanview' -Product 'irfanview' -Query 'IrfanView' -Publisher 'Irfan Skiljan' | Should -Be 5   # Alias
            Get-CpeCandidateScore -Vendor 'gimp' -Product 'gimp_print' -Query 'GIMP' -Publisher 'Contoso' | Should -Be 1
            Get-CpeCandidateScore -Vendor 'microsoft' -Product 'windows_2000_terminal_services' -Query 'Windows Terminal' -Publisher 'Microsoft Corporation' | Should -Be 0
        }
    }
}

Describe 'Get-CpeMappingReport' {
    BeforeEach {
        $script:MapFile = Join-Path $TestDrive "cpe-map-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-CpeMappingPath { $script:MapFile }
    }

    It 'baut den Link zum vorausgefüllten Issue, ohne persönliche Angaben' {
        $record = New-TestRecord -Name "Tool von $env:USERNAME" -Publisher 'Contoso' -WingetId 'Contoso.Tool'
        $record | Set-CpeMapping -Cpe 'cpe:2.3:a:contoso:tool' | Out-Null
        $report = $record | Get-CpeMappingReport
        $report.Url | Should -BeLike 'https://github.com/normbox/Softwareverwaltung/issues/new?template=cpe-zuordnung.yml&*'
        $report.Url | Should -Match 'cpe=cpe%3A2.3%3Aa%3Acontoso%3Atool'
        $report.Url | Should -Match 'winget-id=Contoso.Tool'
        $report.Fields.program | Should -Be 'Tool von %USERNAME%'
        # Nicht auf den ganzen Link prüfen: Der Benutzername kann im Repository-Namen vorkommen.
        $report.Url | Should -Match 'program=Tool%20von%20%25USERNAME%25&'
    }

    It 'meldet ohne bestätigte Zuordnung einen Fehler mit Code' {
        $null = New-TestRecord | Get-CpeMappingReport -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].Exception.Data['Code'] | Should -Be 'NoUserCpeMapping'
    }
}

Describe 'Issue-Formular für „Vorschlag melden“' {
    It 'hat für jedes Feld des Links eine passende Feld-ID' {
        $form = Get-Content "$PSScriptRoot/../../.github/ISSUE_TEMPLATE/cpe-zuordnung.yml" -Raw
        foreach ($id in 'program', 'publisher', 'winget-id', 'version', 'cpe') { $form | Should -Match "(?m)^\s+id: $id\s*$" }
    }
}
