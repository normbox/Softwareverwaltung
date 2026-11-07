BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    $script:Zip = 'cpe:2.3:a:7-zip:7-zip'
    $script:ZipAny = 'cpe:2.3:a:7-zip:7-zip:*:*:*:*:*:*:*:*'

    function New-Match {
        param([string] $Criteria, [bool] $Vulnerable = $true, [string] $EndExcluding)
        $m = [ordered]@{ vulnerable = $Vulnerable; criteria = $Criteria }
        if ($EndExcluding) { $m.versionEndExcluding = $EndExcluding }
        $m
    }

    function New-Config {
        # Konfiguration der NVD: -Node ist eine Liste von Knoten, jeder Knoten eine Liste von cpeMatch-Einträgen.
        param([object[]] $Node, [string] $Operator, [switch] $Negate)
        $c = [ordered]@{ nodes = @($Node | ForEach-Object { [ordered]@{ operator = 'OR'; negate = [bool] $Negate; cpeMatch = @($_) } }) }
        if ($Operator) { $c.operator = $Operator }
        $c
    }

    function New-PlatformCve {
        param([string] $Id, [object[]] $Configuration, [string] $Published = '2025-06-01T00:00:00.000')
        [ordered]@{
            id = $Id; published = $Published
            descriptions = @(@{ lang = 'en'; value = "Test $Id" })
            metrics = @{ cvssMetricV31 = @(@{ type = 'Primary'; cvssData = @{ version = '3.1'; baseScore = 7.5; baseSeverity = 'HIGH' } }) }
            configurations = @($Configuration)
        } | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    }

    # Nur auf macOS: 7-Zip (verwundbar) UND macOS (Umgebung)
    function New-MacOnlyConfig {
        New-Config -Operator AND -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')), @(, @(New-Match 'cpe:2.3:o:apple:macos:-:*:*:*:*:*:*:*' $false))
    }

    function New-CirclRecord {
        param([string] $Id, [hashtable[]] $Block, [string] $Published = '2025-06-01T00:00:00Z')
        @{
            cveMetadata = @{ cveId = $Id; state = 'PUBLISHED'; datePublished = $Published }
            containers  = @{ cna = @{ affected = @($Block); descriptions = @(@{ lang = 'en'; value = "Test $Id" }) } }
        } | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String
    }

    function New-Block {
        param([string] $Vendor, [string] $Product, [string] $LessThan = '130.0', [string[]] $Platforms, [string[]] $Cpes)
        $b = @{ vendor = $Vendor; product = $Product; versions = @(@{ version = '0'; lessThan = $LessThan; status = 'affected'; versionType = 'custom' }) }
        if ($Platforms) { $b.platforms = $Platforms }
        if ($Cpes) { $b.cpes = $Cpes }
        $b
    }
}

Describe 'Get-PlatformFromText' {
    It '<Text> ergibt <Expected>' -ForEach @(
        @{ Text = 'iphone_os'; Expected = 'iOS' }
        @{ Text = 'iOS'; Expected = 'iOS' }
        @{ Text = 'iPadOS'; Expected = 'iPadOS' }
        @{ Text = 'mac_os_x'; Expected = 'macOS' }
        @{ Text = 'macOS'; Expected = 'macOS' }
        @{ Text = 'android'; Expected = 'Android' }
        @{ Text = 'Linux(R580)'; Expected = 'Linux' }
        @{ Text = 'linux_kernel'; Expected = 'Linux' }
        @{ Text = 'chrome_os'; Expected = 'ChromeOS' }
        @{ Text = 'windows'; Expected = 'Windows' }
        @{ Text = 'Windows Server 2019 (Server Core installation)'; Expected = 'Windows' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ T = $Text } { Get-PlatformFromText $T } | Should -Be $Expected
    }

    It 'kennt <Text> nicht (zählt weiter als Treffer)' -ForEach @(
        @{ Text = 'unknown' }, @{ Text = 'x64-based systems' }, @{ Text = '32-bit systems' }, @{ Text = '*' }, @{ Text = '' }, @{ Text = 'iosevka' }, @{ Text = 'linuxmint-tool' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ T = $Text } { Get-PlatformFromText $T } | Should -BeNullOrEmpty
    }
}

Describe 'Plattformfilter der NVD' {
    It 'führt eine CVE nur für macOS als nicht betroffen für Windows' {
        $cve = New-PlatformCve 'CVE-2025-1001' @(New-MacOnlyConfig)
        $check = InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }
        $check.Affected | Should -BeFalse
        $check.OtherPlatform | Should -Be @('macOS')
        # flache Liste, nicht verschachtelt (Should -Be vergleicht Listen flach)
        @($check.OtherPlatform).Count | Should -Be 1
        $check.OtherPlatform[0] | Should -BeOfType [string]
        $s = InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-NvdStatement -Cve $C -CpeBase $B -Version '24.08' }
        $s.Verdict | Should -Be 'NotAffected'
        $s.OtherPlatform | Should -Be @('macOS')
        $s.Note.Code | Should -Be 'OtherPlatformOnly'
    }

    It 'filtert nicht, wenn die Umgebung <Case> enthält' -ForEach @(
        @{ Case = 'Windows'; Env = @('cpe:2.3:o:apple:macos:-:*:*:*:*:*:*:*', 'cpe:2.3:o:microsoft:windows:-:*:*:*:*:*:*:*') }
        @{ Case = 'eine Anwendung'; Env = @('cpe:2.3:a:irfanview:irfanview:4.70:*:*:*:*:*:*:*') }
        @{ Case = 'ein unbekanntes Betriebssystem'; Env = @('cpe:2.3:o:freebsd:freebsd:-:*:*:*:*:*:*:*') }
    ) {
        $config = New-Config -Operator AND -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')), @(, @($Env | ForEach-Object { New-Match $_ $false }))
        $cve = New-PlatformCve 'CVE-2025-1002' @($config)
        $check = InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }
        $check.Affected | Should -BeTrue
        $check.OtherPlatform | Should -BeNullOrEmpty
    }

    It 'filtert nicht bei negiertem Knoten' {
        $config = New-Config -Operator AND -Negate -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')), @(, @(New-Match 'cpe:2.3:o:apple:macos:-:*:*:*:*:*:*:*' $false))
        $cve = New-PlatformCve 'CVE-2025-1003' @($config)
        (InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }).Affected | Should -BeTrue
    }

    It 'führt einen Eintrag mit target_sw <Target> als <Expected>' -ForEach @(
        @{ Target = 'android'; Expected = 'Android' }
        @{ Target = 'iphone_os'; Expected = 'iOS' }
    ) {
        $config = New-Config -Node @(, @(New-Match "cpe:2.3:a:7-zip:7-zip:*:*:*:*:*:${Target}:*:*" -EndExcluding '25.0'))
        $cve = New-PlatformCve 'CVE-2025-1004' @($config)
        $check = InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }
        $check.Affected | Should -BeFalse
        $check.OtherPlatform | Should -Be @($Expected)
    }

    It 'zählt eine CVE, wenn neben macOS auch eine Konfiguration ohne Plattform zutrifft' {
        $plain = New-Config -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0'))
        $cve = New-PlatformCve 'CVE-2025-1005' @((New-MacOnlyConfig), $plain)
        $check = InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }
        $check.Affected | Should -BeTrue
        $check.OtherPlatform | Should -BeNullOrEmpty
    }

    It 'nennt alle Plattformen, wenn jede Konfiguration eine andere Plattform betrifft' {
        $linux = New-Config -Operator AND -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')), @(, @(New-Match 'cpe:2.3:o:linux:linux_kernel:-:*:*:*:*:*:*:*' $false))
        $cve = New-PlatformCve 'CVE-2025-1006' @((New-MacOnlyConfig), $linux)
        (InModuleScope SoftwareInventory -Parameters @{ C = $cve; B = $script:Zip } { Get-CveProductAssessment -Cve $C -CpeBase $B -Version '24.08' }).OtherPlatform | ForEach-Object { $_ | Should -BeOfType [string]; $_ } | Should -Be @('macOS', 'Linux')
    }
}

Describe 'Plattformfilter bei CIRCL' {
    BeforeAll {
        $script:Firefox = 'cpe:2.3:a:mozilla:firefox'
        function Get-Check {
            param($Record, [string] $Base = $script:Firefox, [string] $Version = '120.0')
            InModuleScope SoftwareInventory -Parameters @{ R = $Record; B = $Base; V = $Version } { Get-CirclAssessment -Record $R -CpeBase $B -Version $V }
        }
    }

    It 'überspringt „Firefox for Android“ bei der CPE von Firefox' {
        $check = Get-Check (New-CirclRecord 'CVE-2025-2001' @(New-Block 'Mozilla' 'Firefox for Android'))
        $check.Verdict | Should -Be 'NotAffected'
        $check.OtherPlatform | Should -Be @('Android')
        @($check.OtherPlatform).Count | Should -Be 1
        $check.OtherPlatform[0] | Should -BeOfType [string]
        $s = InModuleScope SoftwareInventory -Parameters @{ R = (New-CirclRecord 'CVE-2025-2001' @(New-Block 'Mozilla' 'Firefox for Android')); B = $script:Firefox } { Get-CirclStatement -Record $R -CpeBase $B -Version '120.0' }
        $s.Verdict | Should -Be 'NotAffected'
        $s.Note.Code | Should -Be 'OtherPlatformOnly'
    }

    It 'wertet Firefox aus, wenn daneben „Firefox for iOS“ steht' {
        $check = Get-Check (New-CirclRecord 'CVE-2025-2002' @((New-Block 'Mozilla' 'Firefox for iOS'), (New-Block 'Mozilla' 'Firefox')))
        $check.Verdict | Should -Be 'Affected'
    }

    It 'schließt bei exakt passendem CPE-Produkt nichts über den Namen aus' {
        $check = Get-Check (New-CirclRecord 'CVE-2025-2003' @(New-Block 'Mozilla' 'Firefox for Android')) -Base 'cpe:2.3:a:mozilla:firefox_for_android'
        $check.Verdict | Should -Be 'Affected'
        $check.PSObject.Properties['OtherPlatform'] | Should -BeNullOrEmpty
    }

    It 'schließt bei passender CPE im Eintrag nichts über den Namen aus' {
        $block = New-Block 'Mozilla' 'Firefox for Mac' -Cpes @('cpe:2.3:a:mozilla:firefox:*:*:*:*:*:*:*:*')
        (Get-Check (New-CirclRecord 'CVE-2025-2004' @($block))).Verdict | Should -Be 'Affected'
    }

    It 'überspringt einen Eintrag, dessen passende CPEs nur Android nennen' {
        $block = New-Block 'Mozilla' 'Firefox' -Cpes @('cpe:2.3:a:mozilla:firefox:*:*:*:*:*:android:*:*')
        (Get-Check (New-CirclRecord 'CVE-2025-2005' @($block))).OtherPlatform | Should -Be @('Android')
    }

    It 'wertet platforms <Platforms> als <Expected>' -ForEach @(
        @{ Platforms = @('macOS'); Expected = 'NotAffected'; Other = @('macOS') }
        @{ Platforms = @('Linux(R580)', 'Android'); Expected = 'NotAffected'; Other = @('Linux', 'Android') }
        @{ Platforms = @('Unknown'); Expected = 'Affected'; Other = @() }
        @{ Platforms = @('x64-based Systems'); Expected = 'Affected'; Other = @() }
        @{ Platforms = @('Windows', 'macOS'); Expected = 'Affected'; Other = @() }
    ) {
        $check = Get-Check (New-CirclRecord 'CVE-2025-2006' @(New-Block 'Mozilla' 'Firefox' -Platforms $Platforms))
        $check.Verdict | Should -Be $Expected
        @($check.PSObject.Properties['OtherPlatform']?.Value) | Should -Be $Other
    }

    It 'überspringt einen Eintrag „n/a“, wenn platforms nur iOS nennt' {
        $check = Get-Check (New-CirclRecord 'CVE-2025-2007' @(New-Block 'n/a' 'n/a' -Platforms @('iOS')))
        $check.Verdict | Should -Be 'NotAffected'
        $check.OtherPlatform | Should -Be @('iOS')
    }
}

Describe 'Get-SoftwareVulnerability mit Plattformfilter' {
    BeforeAll {
        function New-TestRecord {
            InModuleScope SoftwareInventory { New-SoftwareRecord -Name '7-Zip 24.08 (x64)' -Source Registry -Property @{ Version = '24.08'; Publisher = 'Igor Pavlov'; WingetId = '7zip.7zip' } }
        }
        function Use-Setting {
            param([string[]] $Service)
            $script:TestServices = $Service
            Mock -ModuleName SoftwareInventory Read-InventorySetting {
                $s = InModuleScope SoftwareInventory { New-DefaultSetting }
                foreach ($name in $script:TestServices) { $s.Services.$name = $true }
                $s
            }
        }
    }
    BeforeEach {
        Mock -ModuleName SoftwareInventory Read-CpeMapping { @{} }
        Mock -ModuleName SoftwareInventory Save-CheckIndex { }
        $script:Kev = @()
        $script:CveById = @{}
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            switch ($Service) {
                'NVD' {
                    if ("$Uri" -match 'cveId=(?<id>CVE-[\d-]+)') {
                        $c = $script:CveById[$Matches.id]
                        return [pscustomobject] @{ vulnerabilities = @(if ($c) { [pscustomobject] @{ cve = $c } }) }
                    }
                    [pscustomobject] @{ totalResults = $script:Cves.Count; resultsPerPage = $script:Cves.Count; vulnerabilities = @($script:Cves | ForEach-Object { [pscustomobject] @{ cve = $_ } }) }
                }
                'KEV' { [pscustomobject] @{ vulnerabilities = @($script:Kev) } }
                'EPSS' { [pscustomobject] @{ data = @() } }
            }
        }
    }

    It 'nennt Lücken nur für andere Plattformen gesondert, ohne Ampelwirkung' {
        Use-Setting NVD
        $script:Cves = @(
            New-PlatformCve 'CVE-2025-3001' @(New-MacOnlyConfig)
            New-PlatformCve 'CVE-2025-3002' @(New-Config -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')))
        )
        $r = New-TestRecord | Get-SoftwareVulnerability
        @($r.Vulnerabilities | ForEach-Object CveId) | Should -Be @('CVE-2025-3002')
        $r.OtherPlatform.CveId | Should -Be 'CVE-2025-3001'
        $r.OtherPlatform[0].Platforms | Should -Be @('macOS')
        $r.OtherPlatform[0].Platforms.Count | Should -Be 1
        $r.OtherPlatform[0].Note.Text | Should -Be (InModuleScope SoftwareInventory { Get-LocalizedString ReasonOtherPlatformCve 'CVE-2025-3001', 'macOS' })
        $r.OtherPlatform[0].Note.Code | Should -Be 'OtherPlatformCve'
        $r.OtherPlatformNote.Code | Should -Be 'OtherPlatformHidden'
        $r.OtherPlatformNote.Text | Should -Be (InModuleScope SoftwareInventory { Get-LocalizedString ReasonOtherPlatformHiddenOne @(1) })
    }

    It 'meldet einen Widerspruch, wenn die NVD nur macOS und CIRCL betroffen meldet' {
        Use-Setting NVD, CIRCL
        $script:Cves = @(New-PlatformCve 'CVE-2025-3003' @(New-MacOnlyConfig))
        Mock -ModuleName SoftwareInventory Get-CirclCve { @{ 'CVE-2025-3003' = (New-CirclRecord 'CVE-2025-3003' @(New-Block '7-Zip' '7-Zip' -LessThan '25.0')) } }
        $r = New-TestRecord | Get-SoftwareVulnerability
        $v = $r.Vulnerabilities | Where-Object CveId -eq 'CVE-2025-3003'
        $v.Assessment | Should -Be 'PossiblyAffected'
        $v.Note.Code | Should -Be 'SourcesDisagree'
        ($v.Sources | Where-Object Source -eq 'NVD').OtherPlatform | Should -Be @('macOS')
        $r.OtherPlatform | Should -BeNullOrEmpty
    }

    It 'nennt eine CVE, die CIRCL nur für Android führt, wenn die NVD sie nicht meldet' {
        Use-Setting NVD, CIRCL
        $script:Cves = @()
        Mock -ModuleName SoftwareInventory Get-CirclCve { @{ 'CVE-2025-3004' = (New-CirclRecord 'CVE-2025-3004' @(New-Block '7-Zip' '7-Zip' -LessThan '25.0' -Platforms @('Android'))) } }
        $r = New-TestRecord | Get-SoftwareVulnerability
        $r.Vulnerabilities | Should -BeNullOrEmpty
        $r.OtherPlatform.CveId | Should -Be 'CVE-2025-3004'
        $r.OtherPlatform[0].Platforms | Should -Be @('Android')
    }

    Context 'KEV' {
        BeforeEach {
            # Katalogeintrag 7-Zip mit KEV-Zuordnung 7-Zip/7-Zip
            $script:Kev = @([pscustomobject] @{ cveID = 'CVE-2025-4001'; vendorProject = '7-Zip'; product = '7-Zip'; dateAdded = '2025-06-02'; knownRansomwareCampaignUse = 'Unknown'; shortDescription = 'Test' })
            $script:Cves = @()
        }

        It 'widerlegt einen KEV-Treffer, wenn alle Konfigurationen eindeutig andere Plattformen betreffen' {
            Use-Setting NVD, KEV
            $script:CveById['CVE-2025-4001'] = New-PlatformCve 'CVE-2025-4001' @(New-MacOnlyConfig)
            $r = New-TestRecord | Get-SoftwareVulnerability
            @($r.Vulnerabilities | ForEach-Object CveId) | Should -Not -Contain 'CVE-2025-4001'
            $refuted = $r.Refuted | Where-Object CveId -eq 'CVE-2025-4001'
            $refuted.Note.Code | Should -Be 'KevRefutedPlatform'
            $r.OtherPlatform | Should -BeNullOrEmpty
        }

        It 'behält den KEV-Treffer, wenn eine Konfiguration (auch) für Windows gilt' {
            Use-Setting NVD, KEV
            $windows = New-Config -Operator AND -Node @(, @(New-Match $script:ZipAny -EndExcluding '25.0')), @(, @(New-Match 'cpe:2.3:o:microsoft:windows:-:*:*:*:*:*:*:*' $false))
            $script:CveById['CVE-2025-4001'] = New-PlatformCve 'CVE-2025-4001' @((New-MacOnlyConfig), $windows)
            $r = New-TestRecord | Get-SoftwareVulnerability
            $v = $r.Vulnerabilities | Where-Object CveId -eq 'CVE-2025-4001'
            $v.Assessment | Should -Be 'Affected'
            $v.Kev | Should -BeTrue
            $r.Refuted | Should -BeNullOrEmpty
        }
    }
}
