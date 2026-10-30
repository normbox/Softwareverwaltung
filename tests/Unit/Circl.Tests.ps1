BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function ConvertTo-TestObject { param($Value) $Value | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String }

    function New-Cve5 {
        # Minimaler CVE-5-Datensatz wie in der Suche von CIRCL; $Affected = Liste von affected-Blöcken.
        param([string] $Id, [object[]] $Affected = @(), [object[]] $AdpAffected = @(), [string] $Published = '2026-03-01T10:00:00.000Z', [double] $Score = 7.8)
        $record = [ordered]@{
            dataType    = 'CVE_RECORD'
            cveMetadata = @{ cveId = $Id; datePublished = $Published }
            containers  = [ordered]@{
                cna = @{
                    affected     = @($Affected)
                    descriptions = @(@{ lang = 'en'; value = "Test $Id" })
                    metrics      = @(@{ cvssV3_1 = @{ version = '3.1'; baseScore = $Score; baseSeverity = 'HIGH' } })
                }
            }
        }
        if ($AdpAffected) { $record.containers.adp = @(@{ affected = @($AdpAffected) }) }
        ConvertTo-TestObject $record
    }

    function New-Block {
        param([string] $Vendor = '7-Zip', [string] $Product = '7-Zip', [object[]] $Versions, [string[]] $Cpes)
        $b = [ordered]@{ vendor = $Vendor; product = $Product; versions = @($Versions) }
        if ($Cpes) { $b.cpes = $Cpes }
        $b
    }

    $script:Zip = 'cpe:2.3:a:7-zip:7-zip'
}

Describe 'ConvertFrom-CveVersionText' {
    It 'liest <Text> als <Expected>' -ForEach @(
        @{ Text = '< 8.9.6.1'; Expected = '< 8.9.6.1' }
        @{ Text = '<= 26.00'; Expected = '<= 26.00' }
        @{ Text = '>= 9.11, < 26.01'; Expected = '>= 9.11, < 26.01' }
        @{ Text = '> 2.0 and <= 2.4'; Expected = '> 2.0, <= 2.4' }
        @{ Text = '>= 3.0'; Expected = '>= 3.0' }
        @{ Text = 'Fixed in 3.0.7'; Expected = '< 3.0.7' }
        @{ Text = 'fixed in version 2.1'; Expected = '< 2.1' }
        @{ Text = 'VLC media player before 3.0.18.'; Expected = '< 3.0.18' }
        @{ Text = 'versions prior to 4.2.1'; Expected = '< 4.2.1' }
        @{ Text = 'prior to version v1.5'; Expected = '< 1.5' }
        @{ Text = '3.0.20 and earlier'; Expected = '<= 3.0.20' }
        @{ Text = '26.01'; Expected = '= 26.01' }
    ) {
        $range = InModuleScope SoftwareInventory -Parameters @{ T = $Text } { ConvertFrom-CveVersionText $T }
        InModuleScope SoftwareInventory -Parameters @{ R = $range } { Format-VersionRange $R } | Should -Be $Expected
    }

    It 'gibt bei <Text> nichts zurück (nicht auswertbar)' -ForEach @(
        @{ Text = 'n/a' }, @{ Text = 'unspecified' }, @{ Text = '*' }, @{ Text = '0' }, @{ Text = '' },
        @{ Text = 'Fixed in a later release' }, @{ Text = 'all versions' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ T = $Text } { ConvertFrom-CveVersionText $T } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-CveVersionEntry' {
    It 'liest strukturierte Bereiche mit lessThan und lessThanOrEqual' {
        $lt = ConvertTo-TestObject @{ version = '0'; status = 'affected'; lessThan = '26.03'; versionType = 'custom' }
        $le = ConvertTo-TestObject @{ version = '9.0'; status = 'affected'; lessThanOrEqual = '26.01'; versionType = 'semver' }
        InModuleScope SoftwareInventory -Parameters @{ A = $lt; B = $le } {
            Format-VersionRange (ConvertFrom-CveVersionEntry $A) | Should -Be '< 26.03'
            Format-VersionRange (ConvertFrom-CveVersionEntry $B) | Should -Be '>= 9.0, <= 26.01'
        }
    }

    It 'übergeht Einträge ohne Status affected und Git-Commits' {
        $unaffected = ConvertTo-TestObject @{ version = '8.9.4'; status = 'unaffected' }
        $git = ConvertTo-TestObject @{ version = 'abc123'; status = 'affected'; lessThan = 'def456'; versionType = 'git' }
        InModuleScope SoftwareInventory -Parameters @{ A = $unaffected; B = $git } {
            ConvertFrom-CveVersionEntry $A | Should -BeNullOrEmpty
            ConvertFrom-CveVersionEntry $B | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-CirclAssessment' {
    It 'bewertet <Case>' -ForEach @(
        @{ Case = 'Bereich trifft'; Version = '24.8'; Versions = @(@{ version = '0'; status = 'affected'; lessThan = '26.03'; versionType = 'custom' }); Expected = 'Affected' }
        @{ Case = 'Bereich trifft nicht'; Version = '26.5'; Versions = @(@{ version = '0'; status = 'affected'; lessThan = '26.03'; versionType = 'custom' }); Expected = 'NotAffected' }
        @{ Case = 'Textform trifft'; Version = '8.9.6'; Versions = @(@{ version = '< 8.9.6.1'; status = 'affected' }); Expected = 'Affected' }
        @{ Case = 'Freitext nicht betroffen'; Version = '3.0.18'; Versions = @(@{ version = 'Fixed in 3.0.7'; status = 'affected' }); Expected = 'NotAffected' }
        @{ Case = 'nur genannte Version, gleiche'; Version = '26.1'; Versions = @(@{ version = '26.01'; status = 'affected' }); Expected = 'Affected' }
        @{ Case = 'nur genannte Version, installiert neuer'; Version = '26.5'; Versions = @(@{ version = '26.01'; status = 'affected' }); Expected = 'NotAffected' }
        @{ Case = 'nur genannte Version, installiert älter'; Version = '24.8'; Versions = @(@{ version = '26.01'; status = 'affected' }); Expected = 'NotEvaluable' }
        @{ Case = 'ohne Versionsangabe'; Version = '24.8'; Versions = @(@{ version = 'n/a'; status = 'affected' }); Expected = 'NotEvaluable' }
    ) {
        $record = New-Cve5 'CVE-2026-0001' -Affected @(New-Block -Versions $Versions)
        $result = InModuleScope SoftwareInventory -Parameters @{ R = $record; V = $Version; B = $script:Zip } { Get-CirclAssessment -Record $R -CpeBase $B -Version $V }
        $result.Verdict | Should -Be $Expected
    }

    It 'wertet nur Einträge des Produkts aus, nicht die eines anderen Produkts derselben CVE' {
        $record = New-Cve5 'CVE-2026-0002' -Affected @(
            New-Block -Vendor 'RARLAB' -Product 'WinRAR' -Versions @(@{ version = '0'; status = 'affected'; lessThan = '99.0'; versionType = 'custom' })
            New-Block -Versions @(@{ version = '0'; status = 'affected'; lessThan = '24.0'; versionType = 'custom' })
        )
        $result = InModuleScope SoftwareInventory -Parameters @{ R = $record; B = $script:Zip } { Get-CirclAssessment -Record $R -CpeBase $B -Version '24.8' }
        $result.Verdict | Should -Be 'NotAffected'
        $result.Range | Should -Be '< 24.0'
    }

    It 'nutzt die CPE aus der Ergänzung der CISA (ADP) und Einträge ohne Produktnamen nur ersatzweise' {
        $record = New-Cve5 'CVE-2024-46461' -Affected @(New-Block -Vendor 'n/a' -Product 'n/a' -Versions @(@{ version = 'n/a'; status = 'affected' })) `
            -AdpAffected @(New-Block -Vendor 'videolan' -Product 'vlc_media_player' -Cpes 'cpe:2.3:a:videolan:vlc_media_player:*:*:*:*:*:*:*:*' -Versions @(@{ version = '0'; status = 'affected'; lessThanOrEqual = '3.0.20'; versionType = 'custom' }))
        $result = InModuleScope SoftwareInventory -Parameters @{ R = $record } { Get-CirclAssessment -Record $R -CpeBase 'cpe:2.3:a:videolan:vlc_media_player' -Version '3.0.18' }
        $result.Verdict | Should -Be 'Affected'
        $result.Range | Should -Be '<= 3.0.20'
    }

    It 'ist nicht auswertbar, wenn kein Eintrag zum Produkt passt' {
        $record = New-Cve5 'CVE-2026-0003' -Affected @(New-Block -Vendor 'Other' -Product 'Tool' -Versions @(@{ version = '< 99'; status = 'affected' }))
        (InModuleScope SoftwareInventory -Parameters @{ R = $record; B = $script:Zip } { Get-CirclAssessment -Record $R -CpeBase $B -Version '24.8' }).Verdict | Should -Be 'NotEvaluable'
    }
}

Describe 'Get-CirclCve' {
    BeforeAll {
        $script:Npp = 'cpe:2.3:a:notepad-plus-plus:notepad\+\+'
        function New-Row {
            # Zeile der Suche: [id, Datensatz] mit Feldern, die der Bestand nicht braucht (references, problemTypes).
            param([string] $Id, [string] $Note = 'alt', [string] $State = 'PUBLISHED')
            , @($Id.ToLowerInvariant(), [ordered]@{
                    cveMetadata = @{ cveId = $Id; state = $State; datePublished = '2026-01-01T00:00:00Z'; dateUpdated = '2026-02-01T00:00:00Z' }
                    containers  = @{
                        cna = @{
                            affected     = @(@{ vendor = 'notepad-plus-plus'; product = 'notepad++'; versions = @(@{ version = '0'; status = 'affected'; lessThan = '9.0'; versionType = 'custom' }) })
                            descriptions = @(@{ lang = 'en'; value = "$Id $Note" }, @{ lang = 'de'; value = 'Deutsch' })
                            references   = @(@{ url = 'https://example.org' })
                            problemTypes = @(@{ descriptions = @(@{ cweId = 'CWE-79' }) })
                        }
                    }
                })
        }
        function Invoke-Circl {
            param($Setting = $null)
            InModuleScope SoftwareInventory -Parameters @{ B = $script:Npp; S = $Setting } { Get-CirclCve -CpeBase $B -Setting $S }
        }
        function Set-StoreAge {
            # Verschiebt die Abrufzeiten im Bestand um Stunden in die Vergangenheit.
            param([double] $FetchedHours, [double] $FullHours = $FetchedHours)
            InModuleScope SoftwareInventory -Parameters @{ F = $FetchedHours; A = $FullHours } {
                $file = Get-CirclStoreFile -Vendor 'notepad-plus-plus' -Product 'notepad\+\+'
                $store = Read-CirclStore $file
                $store.FetchedAt = [datetime]::UtcNow.AddHours(-$F); $store.FullAt = [datetime]::UtcNow.AddHours(-$A)
                Write-CirclStore -Path $file -Store $store
            }
        }
        function Get-Store {
            InModuleScope SoftwareInventory { Read-CirclStore (Get-CirclStoreFile -Vendor 'notepad-plus-plus' -Product 'notepad\+\+') }
        }
    }
    BeforeEach {
        # Ordner „cache“ unter einem eigenen App-Ordner, damit Invoke-AppDataCleanup ihn findet
        $cache = Join-Path $TestDrive "$([guid]::NewGuid())\cache"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        # Vollständige Suche: $script:FullIds; mit since: $script:SinceRows (oder Fehler bei $script:SinceFails)
        $script:FullIds = @('CVE-2026-0001', 'CVE-2026-0002')
        $script:SinceRows = @()
        $script:SinceFails = $false
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            if ("$Uri" -match '&since=') {
                if ($script:SinceFails) { throw [System.Exception]::new('CIRCL nicht erreichbar') }
                return (@{ cvelistv5 = @($script:SinceRows) } | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String)
            }
            $rows = @($script:FullIds | ForEach-Object { New-Row $_ })
            @{ results = @{ nvd = $rows; cvelistv5 = $rows }; total_count = 2 * $rows.Count; page = 1 } | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String
        }
    }

    It 'blättert alle Seiten durch, maskiert die CPE und fasst doppelte Datensätze zusammen' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            $page = [int] ([regex]::Match("$Uri", '&page=(\d+)').Groups[1].Value)
            $ids = if ($page -eq 1) { 1..50 } else { 51..60 }
            $rows = @($ids | ForEach-Object { , @("cve-2026-$_", @{ cveMetadata = @{ cveId = "CVE-2026-$_" }; containers = @{ cna = @{} } }) })
            $body = @{ results = @{ nvd = $rows; cvelistv5 = $rows }; total_count = 120; page_size = 100; page = $page }
            $body | ConvertTo-Json -Depth 8 | ConvertFrom-Json -DateKind String
        }
        $all = Invoke-Circl
        $all.Count | Should -Be 60
        $all.ContainsKey('CVE-2026-60') | Should -BeTrue
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly -ParameterFilter {
            $Service -eq 'CIRCL' -and $Uri.AbsoluteUri -match '/vulnerability/search/notepad-plus-plus/notepad%5C%2B%5C%2B\?per_page=100&page=\d$'
        }
    }

    It 'speichert nur die ausgewerteten Felder und fragt bei frischem Bestand nicht neu' {
        $first = Invoke-Circl
        $first.Keys | Sort-Object | Should -Be @('CVE-2026-0001', 'CVE-2026-0002')
        $r = (Get-Store).Records['CVE-2026-0001']
        $r.containers.cna.PSObject.Properties.Name | Should -Be @('affected', 'descriptions', 'metrics')
        $r.containers.cna.descriptions.value | Should -Be 'CVE-2026-0001 alt'
        $r.containers.cna.affected[0].versions[0].lessThan | Should -Be '9.0'
        $r.cveMetadata.dateUpdated | Should -Be '2026-02-01T00:00:00Z'

        $second = Invoke-Circl
        $second.Count | Should -Be 2
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly
    }

    It 'lädt nach Ablauf nur die Änderungen seit dem letzten Abruf und führt sie zusammen' {
        Invoke-Circl | Out-Null
        Set-StoreAge -FetchedHours 30 -FullHours 30
        $since = [datetime]::UtcNow.AddHours(-30).ToString('yyyy-MM-dd')
        $script:SinceRows = @((New-Row 'CVE-2026-0001' -Note 'neu'), (New-Row 'CVE-2026-0003'), (New-Row 'CVE-2026-0002' -State 'REJECTED'))
        $all = Invoke-Circl
        $all.Keys | Sort-Object | Should -Be @('CVE-2026-0001', 'CVE-2026-0003')
        $all['CVE-2026-0001'].containers.cna.descriptions.value | Should -Be 'CVE-2026-0001 neu'
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -match "&page=1&since=$since$" }
        $store = Get-Store
        ([datetime]::UtcNow - $store.FetchedAt).TotalMinutes | Should -BeLessThan 5
        ([datetime]::UtcNow - $store.FullAt).TotalHours | Should -BeGreaterThan 29   # kein vollständiger Abruf
    }

    It 'lädt vollständig, wenn der Bestand <Case> ist' -ForEach @(
        @{ Case = 'beschädigt' }, @{ Case = 'aufgeräumt' }
    ) {
        Invoke-Circl | Out-Null
        Set-StoreAge -FetchedHours 30 -FullHours 30
        $file = InModuleScope SoftwareInventory { Get-CirclStoreFile -Vendor 'notepad-plus-plus' -Product 'notepad\+\+' }
        if ($Case -eq 'beschädigt') { Set-Content -LiteralPath $file -Value '{"FullAt":"2026-10-01T00:00:00Z","Records":[{"cveMeta' }
        else {
            (Get-Item -LiteralPath $file).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-60)
            InModuleScope SoftwareInventory -Parameters @{ R = (Split-Path (Split-Path $file)) | Split-Path } { Invoke-AppDataCleanup -RetentionDays 30 -MaxSizeMB 100 -Root $R } | Out-Null
            Test-Path -LiteralPath $file | Should -BeFalse
        }
        $script:FullIds = @('CVE-2026-0001', 'CVE-2026-0002', 'CVE-2026-0004')
        $script:SinceRows = @(New-Row 'CVE-2026-0003')   # dürfte nie genutzt werden
        $all = Invoke-Circl
        $all.Keys | Sort-Object | Should -Be @('CVE-2026-0001', 'CVE-2026-0002', 'CVE-2026-0004')
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { "$Uri" -match '&since=' }
        ([datetime]::UtcNow - (Get-Store).FullAt).TotalMinutes | Should -BeLessThan 5
    }

    It 'setzt das Datum nicht weiter, wenn das Nachladen abbricht, und nutzt den alten Bestand als veraltet' {
        Invoke-Circl | Out-Null
        Set-StoreAge -FetchedHours 30 -FullHours 30
        $before = Get-Store
        $script:SinceFails = $true
        $trace = InModuleScope SoftwareInventory -Parameters @{ B = $script:Npp } { Invoke-WithCheckTrace { Get-CirclCve -CpeBase $B -Setting $null } }
        $trace.Output.Keys | Sort-Object | Should -Be @('CVE-2026-0001', 'CVE-2026-0002')
        $trace.Trace[0].Stale | Should -BeTrue
        $after = Get-Store
        $after.FetchedAt | Should -Be $before.FetchedAt
        $after.FullAt | Should -Be $before.FullAt

        # Beim nächsten Mal wieder ab demselben Tag
        $script:SinceFails = $false
        Invoke-Circl | Out-Null
        $since = $before.FetchedAt.ToString('yyyy-MM-dd')
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly -ParameterFilter { "$Uri" -match "&since=$since$" }
    }

    It 'meldet den Fehler, wenn der erste Abruf abbricht, und schreibt keinen Bestand' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            if ("$Uri" -match '&page=2') { throw [System.Exception]::new('CIRCL nicht erreichbar') }
            $rows = @(1..50 | ForEach-Object { New-Row "CVE-2026-1$('{0:d3}' -f $_)" })
            @{ results = @{ nvd = $rows; cvelistv5 = $rows }; total_count = 300; page = 1 } | ConvertTo-Json -Depth 12 | ConvertFrom-Json -DateKind String
        }
        { Invoke-Circl } | Should -Throw '*nicht erreichbar*'
        Get-Store | Should -BeNullOrEmpty
    }

    It 'lädt nach <Days> Tagen vollständig' -ForEach @(@{ Days = 31 }) {
        Invoke-Circl | Out-Null
        Set-StoreAge -FetchedHours 30 -FullHours ($Days * 24)
        Invoke-Circl | Out-Null
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { "$Uri" -match '&since=' }
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly
    }

    It 'lädt bei Neu prüfen vollständig, je Produkt einmal im Lauf' {
        Invoke-Circl | Out-Null
        InModuleScope SoftwareInventory -Parameters @{ B = $script:Npp } {
            $owner = Enter-CacheRefresh
            try { Get-CirclCve -CpeBase $B -Setting $null | Out-Null; Get-CirclCve -CpeBase $B -Setting $null | Out-Null }
            finally { Exit-CacheRefresh $owner }
        }
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { "$Uri" -match '&since=' }
    }

    It 'lädt vollständig, wenn das Blättern mit since keine neuen Datensätze liefert' {
        Invoke-Circl | Out-Null
        Set-StoreAge -FetchedHours 30 -FullHours 30
        # Volle Seite, die auf jeder Seite gleich bleibt (page wird nicht beachtet)
        $script:SinceRows = @(1..100 | ForEach-Object { New-Row "CVE-2026-2$('{0:d3}' -f $_)" })
        $all = Invoke-Circl
        $all.Keys | Sort-Object | Should -Be @('CVE-2026-0001', 'CVE-2026-0002')
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly -ParameterFilter { "$Uri" -match '&since=' }
        ([datetime]::UtcNow - (Get-Store).FullAt).TotalMinutes | Should -BeLessThan 5
    }
}

Describe 'Clear-CheckCache und der CIRCL-Bestand' {
    BeforeAll {
        function New-ZipRecord {
            param([string] $Version)
            InModuleScope SoftwareInventory -Parameters @{ V = $Version } { New-SoftwareRecord -Name "7-Zip $V (x64)" -Source Registry -Property @{ Version = $V; Publisher = 'Igor Pavlov'; WingetId = '7zip.7zip' } }
        }
    }
    BeforeEach {
        $cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Read-CpeMapping { @{} }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.CIRCL = $true; $s }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            if ("$Uri" -match '&since=') { return [pscustomobject] @{ cvelistv5 = @() } }
            $record = New-Cve5 'CVE-2026-5000' -Affected @(New-Block -Versions @(@{ version = '0'; status = 'affected'; lessThan = '25.0'; versionType = 'custom' }))
            [pscustomobject] @{ results = [pscustomobject] @{ cvelistv5 = @(, @('cve-2026-5000', $record)) }; total_count = 1; page = 1 }
        }
    }

    It 'behält den Bestand, lädt nur per since nach und bewertet die neue Version neu' {
        $old = New-ZipRecord '24.08' | Get-SoftwareVulnerability
        $old.Vulnerabilities.CveId | Should -Be 'CVE-2026-5000'
        $store = InModuleScope SoftwareInventory { Get-CirclStoreFile -Vendor '7-zip' -Product '7-zip' }

        New-ZipRecord '24.08' | Clear-CheckCache -Confirm:$false
        Test-Path -LiteralPath $store | Should -BeTrue
        Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($store, '.due')) | Should -BeTrue

        # Nach dem Update: neue Version, Bestand noch frisch, trotzdem einmal nachgeladen
        $new = New-ZipRecord '25.01' | Get-SoftwareVulnerability
        $new.Status | Should -Be 'Checked'
        $new.Vulnerabilities | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -match '&since=' }
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -notmatch '&since=' }
        Test-Path -LiteralPath ([System.IO.Path]::ChangeExtension($store, '.due')) | Should -BeFalse
    }
}

Describe 'Merge-SourceStatement' {
    BeforeAll {
        function New-Statement {
            param([string] $Source, [string] $Verdict, [string] $Weight)
            InModuleScope SoftwareInventory -Parameters @{ S = $Source; V = $Verdict; W = $Weight } {
                New-SourceStatement -Source $S -Verdict $V -CveId 'CVE-2026-0001' -Weight $W
            }
        }
    }

    It 'meldet bei betroffen und nicht betroffen einen Widerspruch statt zu widerlegen' {
        $m = InModuleScope SoftwareInventory -Parameters @{ L = @((New-Statement NVD Affected), (New-Statement CIRCL NotAffected)) } { Merge-SourceStatement -Statement $L -CveId 'CVE-2026-0001' }
        $m.Assessment | Should -Be 'PossiblyAffected'
        $m.Disagree | Should -BeTrue
        $m.Note.Code | Should -Be 'SourcesDisagree'
    }

    It 'bewertet <Case> als <Expected>' -ForEach @(
        @{ Case = 'beide betroffen'; A = @('NVD', 'Affected', ''); B = @('CIRCL', 'Affected', ''); Expected = 'Affected' }
        @{ Case = 'betroffen und unbekannt'; A = @('NVD', 'Unknown', ''); B = @('CIRCL', 'Affected', ''); Expected = 'Affected' }
        @{ Case = 'nicht betroffen gegen nicht auswertbar'; A = @('NVD', 'NotAffected', ''); B = @('CIRCL', 'NotEvaluable', 'PossiblyAffected'); Expected = $null }
        @{ Case = 'nur nicht auswertbar, jung'; A = @('NVD', 'Unknown', ''); B = @('CIRCL', 'NotEvaluable', 'PossiblyAffected'); Expected = 'PossiblyAffected' }
        @{ Case = 'nur nicht auswertbar, alt'; A = @('CIRCL', 'NotEvaluable', 'Informational'); B = $null; Expected = 'Informational' }
    ) {
        $list = @((New-Statement @A)) + @(if ($B) { New-Statement @B })
        $m = InModuleScope SoftwareInventory -Parameters @{ L = $list } { Merge-SourceStatement -Statement $L -CveId 'CVE-2026-0001' }
        if ($Expected) { $m.Assessment | Should -Be $Expected; $m.Disagree | Should -BeFalse } else { $m | Should -BeNullOrEmpty }
    }

    It 'nennt bei CIRCL die Quelle mit Lizenz (CC BY 4.0) und verlinkt die CVE' {
        $s = New-Statement CIRCL Affected
        $s.Attribution.Code | Should -Be 'AttributionCIRCL'
        $s.Attribution.Text | Should -Match 'CVE-Programm über CIRCL, CC BY 4\.0'
        $s.Url | Should -Be 'https://vulnerability.circl.lu/vuln/CVE-2026-0001'
    }
}

Describe 'Get-SoftwareVulnerability mit NVD und CIRCL' {
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
        function New-NvdCve {
            param([string] $Id, [hashtable] $Bound)
            $match = @{ criteria = 'cpe:2.3:a:7-zip:7-zip:*:*:*:*:*:*:*:*'; vulnerable = $true } + $Bound
            ConvertTo-TestObject ([ordered]@{
                    id = $Id; published = '2026-01-10T10:00:00.000'
                    descriptions = @(@{ lang = 'en'; value = "NVD $Id" })
                    metrics = @{ cvssMetricV31 = @(@{ type = 'Primary'; cvssData = @{ version = '3.1'; baseScore = 7.0; baseSeverity = 'HIGH' } }) }
                    configurations = @(@{ nodes = @(@{ operator = 'OR'; cpeMatch = @($match) }) })
                })
        }
        function New-ZipCve5 {
            param([string] $Id, [string] $LessThan, [string] $Version = '0', [string] $Published = '2026-02-01T10:00:00.000Z')
            $v = @{ version = $Version; status = 'affected' }
            if ($LessThan) { $v.lessThan = $LessThan; $v.versionType = 'custom' }
            New-Cve5 $Id -Affected @(New-Block -Versions @($v)) -Published $Published
        }
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            switch ($Service) {
                'NVD' {
                    if ("$Uri" -match 'virtualMatchString=') {
                        $all = @($script:NvdById.Values)
                        return [pscustomobject] @{ totalResults = $all.Count; resultsPerPage = $all.Count; vulnerabilities = @($all | ForEach-Object { [pscustomobject] @{ cve = $_ } }) }
                    }
                    if ("$Uri" -match 'cveId=(?<id>CVE-[\d-]+)') {
                        $c = $script:NvdById[$Matches.id]
                        return [pscustomobject] @{ vulnerabilities = @(if ($c) { [pscustomobject] @{ cve = $c } }) }
                    }
                    [pscustomobject] @{ totalResults = $script:NvdCves.Count; resultsPerPage = $script:NvdCves.Count; vulnerabilities = @($script:NvdCves | ForEach-Object { [pscustomobject] @{ cve = $_ } }) }
                }
                'CIRCL' {
                    if ($script:CirclFails) { throw [System.Exception]::new('CIRCL nicht erreichbar') }
                    $rows = @($script:CirclRecords | ForEach-Object { , @($_.cveMetadata.cveId.ToLowerInvariant(), $_) })
                    [pscustomobject] @{ results = [pscustomobject] @{ cvelistv5 = $rows }; total_count = $rows.Count; page = 1 }
                }
            }
        }
    }
    BeforeEach {
        $script:NvdCves = @(); $script:NvdById = @{}; $script:CirclRecords = @(); $script:CirclFails = $false
        $cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Read-CpeMapping { @{} }
        Mock -ModuleName SoftwareInventory Save-CheckIndex { }
    }

    It 'zählt eine CVE beider Quellen einmal und zeigt beide Angaben' {
        Use-Setting NVD, CIRCL
        $script:NvdCves = @(New-NvdCve 'CVE-2026-1000' @{ versionEndExcluding = '24.09' })
        $script:CirclRecords = @(New-ZipCve5 'CVE-2026-1000' -LessThan '24.09')
        $r = New-TestRecord | Get-SoftwareVulnerability
        $r.Status | Should -Be 'Checked'
        @($r.Vulnerabilities).Count | Should -Be 1
        $v = $r.Vulnerabilities[0]
        $v.Assessment | Should -Be 'Affected'
        $v.SourcesDisagree | Should -BeFalse
        ($v.Sources | ForEach-Object { "$($_.Source)=$($_.Verdict) $($_.Range)" }) | Should -Be @('NVD=Affected < 24.09', 'CIRCL=Affected < 24.09')
        ($v.Sources | Where-Object Source -eq CIRCL).Attribution.Text | Should -Match 'CC BY 4\.0'
    }

    It 'meldet einen Widerspruch, wenn die NVD betroffen und CIRCL nicht betroffen meldet' {
        Use-Setting NVD, CIRCL
        $script:NvdCves = @(New-NvdCve 'CVE-2026-1001' @{ versionEndExcluding = '24.09' })
        $script:CirclRecords = @(New-ZipCve5 'CVE-2026-1001' -LessThan '24.0')
        $r = New-TestRecord | Get-SoftwareVulnerability
        @($r.Vulnerabilities).Count | Should -Be 1
        $v = $r.Vulnerabilities[0]
        $v.Assessment | Should -Be 'PossiblyAffected'
        $v.SourcesDisagree | Should -BeTrue
        $rating = InModuleScope SoftwareInventory -Parameters @{ V = $r } { Get-RatingFromResult -UpdateStatus $null -VulnerabilityStatus $V }
        $rating.Rating | Should -Be 'Yellow'
        $rating.Reasons.Code | Should -Contain 'SourcesDisagree'
    }

    It 'schlägt CIRCL-Treffer in der NVD nach: widersprochen, unbekannt' {
        Use-Setting NVD, CIRCL
        $script:CirclRecords = @((New-ZipCve5 'CVE-2026-2001' -LessThan '25.0'), (New-ZipCve5 'CVE-2026-2002' -LessThan '25.0'))
        $script:NvdById = @{ 'CVE-2026-2001' = (New-NvdCve 'CVE-2026-2001' @{ versionEndExcluding = '23.0' }) }
        $r = New-TestRecord | Get-SoftwareVulnerability
        $byId = @{}; foreach ($v in $r.Vulnerabilities) { $byId[$v.CveId] = $v }
        $byId['CVE-2026-2001'].SourcesDisagree | Should -BeTrue
        ($byId['CVE-2026-2001'].Sources | Where-Object Source -eq NVD).Verdict | Should -Be 'NotAffected'
        $byId['CVE-2026-2002'].Assessment | Should -Be 'Affected'
        ($byId['CVE-2026-2002'].Sources | Where-Object Source -eq NVD).Verdict | Should -Be 'Unknown'
        $byId['CVE-2026-2002'].Description | Should -Be 'Test CVE-2026-2002'
        $byId['CVE-2026-2002'].Score | Should -Be 7.8
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -match 'virtualMatchString=cpe%3A2\.3%3Aa%3A7-zip%3A7-zip&' }
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { "$Uri" -match 'cveId=' }
    }

    It 'fragt bei vielen CIRCL-Treffern die NVD nur einmal je Produkt statt je CVE' {
        Use-Setting NVD, CIRCL
        $script:CirclRecords = @(1..40 | ForEach-Object { New-ZipCve5 "CVE-2026-3$('{0:d3}' -f $_)" -LessThan '25.0' })
        $r = New-TestRecord | Get-SoftwareVulnerability
        @($r.Vulnerabilities).Count | Should -Be 40
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 2 -Exactly -ParameterFilter { $Service -eq 'NVD' }   # Versionssuche + Sammelabfrage
    }

    It 'prüft mit CIRCL allein, wenn die NVD aus ist, und zeigt Altdaten nur als Hinweis' {
        Use-Setting CIRCL
        $script:CirclRecords = @((New-ZipCve5 'CVE-2026-3001' -LessThan '25.0'), (New-ZipCve5 'CVE-2012-0001' -Version 'n/a' -Published '2012-05-01T00:00:00.000Z'))
        $r = New-TestRecord | Get-SoftwareVulnerability
        $r.Status | Should -Be 'Checked'
        ($r.Vulnerabilities | Where-Object CveId -eq 'CVE-2026-3001').Sources.Source | Should -Be 'CIRCL'
        ($r.Vulnerabilities | Where-Object CveId -eq 'CVE-2012-0001').Assessment | Should -Be 'Informational'
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { $Service -eq 'NVD' }
    }

    It 'übergeht alte CIRCL-Einträge ohne Versionsangabe, wenn die NVD geprüft hat' {
        Use-Setting NVD, CIRCL
        $script:CirclRecords = @(New-ZipCve5 'CVE-2012-0001' -Version 'n/a' -Published '2012-05-01T00:00:00.000Z')
        $r = New-TestRecord | Get-SoftwareVulnerability
        $r.Vulnerabilities | Should -BeNullOrEmpty
        Should -Invoke -ModuleName SoftwareInventory Invoke-ServiceRequest -Times 0 -Exactly -ParameterFilter { "$Uri" -match 'cveId=' }
    }

    It 'gilt als geprüft, wenn eine Quelle ausfällt, und nennt den Ausfall' {
        Use-Setting NVD, CIRCL
        $script:CirclFails = $true
        $script:NvdCves = @(New-NvdCve 'CVE-2026-1000' @{ versionEndExcluding = '24.09' })
        $r = New-TestRecord | Get-SoftwareVulnerability
        $r.Status | Should -Be 'Checked'
        ($r.Notes | Where-Object Code -eq 'ServiceUnavailable').Args | Should -Contain 'CIRCL'
        $r.Vulnerabilities[0].Sources.Source | Should -Be 'NVD'
    }
}
