BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    # Schreibverhalten des Zwischenspeichers bei Scans (Etappe A): wie viele Dateien ein Scan anlegt oder
    # neu schreibt. Grund: Viele Neuschreibungen in kurzer Folge lösen Verhaltensschutz-Programme aus
    # (Fehlalarm „Ransomware“). Dienste sind nachgebildet; geschrieben wird echt, in ein Testverzeichnis.

    function New-Cve {
        param([string] $Id, [string] $End)
        [pscustomobject] @{
            id             = $Id
            published      = '2025-01-25T05:15:09.000'
            descriptions   = @([pscustomobject] @{ lang = 'en'; value = "Test $Id" })
            metrics        = [pscustomobject] @{ cvssMetricV31 = @([pscustomobject] @{ type = 'Primary'; cvssData = [pscustomobject] @{ version = '3.1'; baseScore = 7.5; baseSeverity = 'HIGH' } }) }
            configurations = @([pscustomobject] @{ nodes = @([pscustomobject] @{ operator = 'OR'; cpeMatch = @(
                                [pscustomobject] @{ criteria = 'cpe:2.3:a:7-zip:7-zip:*:*:*:*:*:*:*:*'; vulnerable = $true; versionEndExcluding = $End }) }) })
        }
    }

    function Use-FakeServices {
        # Antworten nach Adresse; EPSS antwortet für genau die angefragten CVEs.
        Mock -ModuleName SoftwareInventory Invoke-WebRequest {
            $u = "$Uri"
            $body = if ($u -match 'cveId=(?<id>CVE-[\d-]+)') { @{ totalResults = 0; resultsPerPage = 0; vulnerabilities = @() } }
            elseif ($u -match 'nvd\.nist\.gov.*cpeName=') {
                $cves = @($script:Cves | ForEach-Object { @{ cve = $_ } })
                @{ totalResults = $cves.Count; resultsPerPage = $cves.Count; startIndex = 0; vulnerabilities = $cves }
            }
            elseif ($u -match 'known_exploited') { @{ vulnerabilities = @() } }
            elseif ($u -match 'epss.*cve=(?<ids>[^&]+)') {
                @{ data = @([uri]::UnescapeDataString($Matches.ids) -split ',' | ForEach-Object { @{ cve = $_; epss = '0.1'; percentile = '0.5' } }) }
            }
            else { throw "Unerwartete Adresse im Test: $u" }
            [pscustomobject] @{ StatusCode = 200; Content = ($body | ConvertTo-Json -Depth 20 -Compress); Headers = @{} }
        }
    }

    function New-ZipRecord {
        param([string] $Version, [string] $Key)
        InModuleScope SoftwareInventory -Parameters @{ V = $Version; K = $Key } {
            New-SoftwareRecord -Name "7-Zip $V (x64)" -Source Registry -Property @{ Version = $V; Publisher = 'Igor Pavlov'; RegistryKey = $K }
        }
    }

    function Get-CacheState {
        # Datei → letzte Schreibzeit; nur Dateien, keine Ordner.
        $state = @{}
        if (Test-Path -LiteralPath $script:Cache) {
            foreach ($f in Get-ChildItem -LiteralPath $script:Cache -File -Recurse) { $state[$f.FullName] = $f.LastWriteTimeUtc }
        }
        $state
    }

    function Invoke-Scan {
        # Ein „Scan“ über Get-SecurityRating; liefert die angelegten bzw. neu geschriebenen Dateien.
        $past = [datetime]::UtcNow.AddMinutes(-10)
        foreach ($f in Get-ChildItem -LiteralPath $script:Cache -File -Recurse -ErrorAction SilentlyContinue) { $f.LastWriteTimeUtc = $past }
        $before = Get-CacheState
        $null = $script:Records | Get-SecurityRating
        $after = Get-CacheState
        [pscustomobject] @{
            Created   = @($after.Keys | Where-Object { -not $before.ContainsKey($_) })
            Rewritten = @($after.Keys | Where-Object { $before.ContainsKey($_) -and $after[$_] -gt $past })
            Removed   = @($before.Keys | Where-Object { -not $after.ContainsKey($_) })
        }
    }

    function Format-Writes {
        param($Result)
        $all = @($Result.Created) + @($Result.Rewritten)
        $groups = $all | ForEach-Object { Split-Path -Leaf (Split-Path -Parent $_) } | Group-Object | ForEach-Object { "$($_.Name)=$($_.Count)" }
        "neu $(@($Result.Created).Count), neu geschrieben $(@($Result.Rewritten).Count), gelöscht $(@($Result.Removed).Count) ($($groups -join ', '))"
    }
}

Describe 'Schreibvorgänge des Zwischenspeichers je Scan' {
    BeforeEach {
        $script:Cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $script:Cache }
        Mock -ModuleName SoftwareInventory Start-Sleep { }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Mock -ModuleName SoftwareInventory Read-InventorySetting {
            $s = InModuleScope SoftwareInventory { New-DefaultSetting }
            foreach ($name in 'NVD', 'KEV', 'EPSS') { $s.Services.$name = $true }
            $s
        }
        $script:Cves = @(New-Cve 'CVE-2025-0411' '24.09'; New-Cve 'CVE-2025-0412' '25.00')
        Use-FakeServices
        $script:Records = @(
            New-ZipRecord '24.08' 'HKLM\Test\Zip1'
            New-ZipRecord '23.01' 'HKLM\Test\Zip2'
            New-ZipRecord '22.00' 'HKLM\Test\Zip3'
        )
    }

    It 'schreibt beim zweiten Scan innerhalb der Haltbarkeit nichts' {
        $first = Invoke-Scan
        Write-Host "  Erster Scan:  $(Format-Writes $first)"
        $second = Invoke-Scan
        Write-Host "  Zweiter Scan: $(Format-Writes $second)"
        @($second.Created) + @($second.Rewritten) | Should -BeNullOrEmpty
    }

    It 'schreibt den Index je Programm höchstens einmal je Scan und nur bei Änderung' {
        Mock -ModuleName SoftwareInventory Write-CheckIndexFile {
            New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
            [System.IO.File]::WriteAllText($Path, $Text)
        }
        $null = $script:Records | Get-SecurityRating
        # Drei Programme: je ein Schreibvorgang für Update- und Lückenprüfung zusammen.
        Should -Invoke -ModuleName SoftwareInventory Write-CheckIndexFile -Times 3 -Exactly

        # Nur für ein Programm ändern sich die benutzten Einträge: genau eine Datei wird neu geschrieben.
        $script:Records[0].Version = '24.07'
        $null = $script:Records | Get-SecurityRating
        Should -Invoke -ModuleName SoftwareInventory Write-CheckIndexFile -Times 4 -Exactly
    }

    It 'schreibt den Index auch nach einem Abbruch für das bis dahin Geprüfte' {
        Mock -ModuleName SoftwareInventory Get-SoftwareVulnerability { throw 'Abbruch' }
        Mock -ModuleName SoftwareInventory Test-SoftwareUpdate {
            InModuleScope SoftwareInventory -Parameters @{ R = $InputObject } {
                foreach ($r in $R) { Save-CheckIndex -Record $r -Kind Update -Trace @([pscustomobject] @{ Service = 'GitHub'; File = 'C:\x\gh.json' }) }
            }
        }
        { $script:Records | Get-SecurityRating } | Should -Throw '*Abbruch*'
        @(Get-ChildItem -LiteralPath (Join-Path $script:Cache 'index') -File).Count | Should -Be 3
        InModuleScope SoftwareInventory { $script:CheckIndexBatch } | Should -BeNullOrEmpty
    }

    It 'legt für EPSS eine Datei an, auch wenn eine neue CVE dazukommt' {
        $null = Invoke-Scan
        $script:Cves = @($script:Cves) + @(New-Cve 'CVE-2026-0001' '26.00')
        # NVD-Antwort ist zwischengespeichert; neu abfragen, damit die neue CVE ankommt.
        Get-ChildItem -LiteralPath (Join-Path $script:Cache 'NVD') -File | Remove-Item
        $second = Invoke-Scan
        Write-Host "  Mit neuer CVE: $(Format-Writes $second)"
        @(Get-ChildItem -LiteralPath (Join-Path $script:Cache 'EPSS') -File).Count | Should -Be 1
    }
}

Describe 'EPSS-Werte in einer Datei je CVE' {
    BeforeAll {
        function Get-Epss([string[]] $Id) {
            InModuleScope SoftwareInventory -Parameters @{ I = $Id; S = $script:Setting } { Get-EpssScore -CveId $I -Setting $S }
        }

        function Set-EpssStore([hashtable] $Scores) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $script:Store) -Force | Out-Null
            @{ Version = 1; Scores = $Scores } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:Store -Encoding utf8NoBOM
        }
    }

    BeforeEach {
        $script:Cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        $script:Logs = Join-Path $TestDrive "local-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $script:Cache }
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $script:Logs }
        Mock -ModuleName SoftwareInventory Start-Sleep { }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Use-FakeServices
        $script:Setting = InModuleScope SoftwareInventory { $s = New-DefaultSetting; $s.Services.EPSS = $true; $s }
        $script:Store = Join-Path $script:Cache 'EPSS\scores.json'
    }

    It 'fragt nur fehlende CVEs ab und merkt sich auch CVEs ohne Wert' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{"data":[{"cve":"CVE-2025-0001","epss":"0.2","percentile":"0.6"}]}'; Headers = @{} } }
        $first = Get-Epss 'CVE-2025-0001', 'cve-2025-0002'
        $first['CVE-2025-0001'].Epss | Should -Be 0.2
        $first['CVE-2025-0002'].Epss | Should -BeNullOrEmpty
        $null = Get-Epss 'CVE-2025-0001', 'CVE-2025-0002'
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:Store) -File).Name | Should -Be 'scores.json'
    }

    It 'fragt abgelaufene Werte neu ab, bei Neu prüfen jede CVE einmal je Lauf' {
        Set-EpssStore @{
            'CVE-2025-0001' = @{ Epss = 0.1; Percentile = 0.5; FetchedAt = [datetime]::UtcNow.AddHours(-30).ToString('o') }
            'CVE-2025-0002' = @{ Epss = 0.1; Percentile = 0.5; FetchedAt = [datetime]::UtcNow.AddHours(-1).ToString('o') }
        }
        $null = Get-Epss 'CVE-2025-0001', 'CVE-2025-0002'
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { "$Uri" -like '*cve=CVE-2025-0001' }

        InModuleScope SoftwareInventory -Parameters @{ S = $script:Setting } {
            $owner = Enter-CacheRefresh
            try { 1..2 | ForEach-Object { $null = Get-EpssScore -CveId 'CVE-2025-0001', 'CVE-2025-0002' -Setting $S } }
            finally { Exit-CacheRefresh $owner }
        }
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 2 -Exactly
    }

    It 'nimmt offline die gespeicherten Werte mit ihrem Alter' {
        $old = [datetime]::UtcNow.AddHours(-30)
        Set-EpssStore @{ 'CVE-2025-0001' = @{ Epss = 0.3; Percentile = 0.7; FetchedAt = $old.ToString('o') } }
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('Keine Verbindung') }
        $r = Get-Epss 'CVE-2025-0001'
        $r['CVE-2025-0001'].Epss | Should -Be 0.3
        $r['CVE-2025-0001'].FetchedAt | Should -BeLessThan ([datetime]::UtcNow.AddHours(-29))
        { Get-Epss 'CVE-2025-0001', 'CVE-2025-0009' } | Should -Throw
    }

    It 'behandelt eine unlesbare Datei als leer, mit Eintrag im Fehlerprotokoll und ohne Meldung' {
        New-Item -ItemType Directory -Path (Split-Path -Parent $script:Store) -Force | Out-Null
        Set-Content -LiteralPath $script:Store -Value '{"Version":1,"Scores":{"CVE-2025' -NoNewline
        $all = @(Get-Epss 'CVE-2025-0001' 3>&1)
        $all | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | Should -BeNullOrEmpty
        $scores = $all | Where-Object { $_ -is [hashtable] } | Select-Object -First 1
        $scores['CVE-2025-0001'].Epss | Should -Be 0.1
        $log = Get-ChildItem -LiteralPath (Join-Path $script:Logs 'logs') -Filter 'app-errors-*.log' | Get-Content -Raw
        $log | Should -BeLike '*Modul/EPSS*scores.json*'
        (Get-Content -LiteralPath $script:Store -Raw | ConvertFrom-Json).Scores.'CVE-2025-0001'.Epss | Should -Be 0.1
    }

    It 'zeigt bei „geprüft vor“ das tatsächliche Alter der EPSS-Werte und führt EPSS nicht im Index' {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $script:Setting.Services.NVD = $true; $script:Setting }
        $script:Cves = @(New-Cve 'CVE-2025-0411' '24.09')
        $old = [datetime]::UtcNow.AddHours(-10)
        Set-EpssStore @{ 'CVE-2025-0411' = @{ Epss = 0.3; Percentile = 0.7; FetchedAt = $old.ToString('o') } }
        $v = New-ZipRecord '24.08' 'HKLM\Test\Zip1' | Get-SoftwareVulnerability
        $v.Vulnerabilities[0].Epss | Should -Be 0.3
        $v.CheckedAt | Should -BeLessThan ([datetime]::UtcNow.AddHours(-9))
        $v.CheckStale | Should -BeFalse
        $index = Get-ChildItem -LiteralPath (Join-Path $script:Cache 'index') -File | Get-Content -Raw
        $index | Should -Not -BeLike '*EPSS*'
    }

    It 'löscht die gemeinsame EPSS-Datei nie beim Verwerfen eines Programms' {
        Set-EpssStore @{ 'CVE-2025-0001' = @{ Epss = 0.3; Percentile = 0.7; FetchedAt = [datetime]::UtcNow.ToString('o') } }
        $record = New-ZipRecord '24.08' 'HKLM\Test\Zip1'
        InModuleScope SoftwareInventory -Parameters @{ R = $record; F = $script:Store } {
            # Älterer Index, der die EPSS-Datei nennt
            Write-CheckIndex -Path (Get-CheckIndexFile $R) -Change @{ Vulnerability = @($F) }
        }
        $record | Clear-CheckCache -Confirm:$false
        Test-Path -LiteralPath $script:Store | Should -BeTrue
    }
}
