BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-EnabledSetting {
        param([string[]] $Service, [hashtable] $Hours = @{})
        $s = InModuleScope SoftwareInventory { New-DefaultSetting }
        foreach ($name in $Service) { $s.Services.$name = $true }
        foreach ($k in $Hours.Keys) { $s.CacheHours.$k = $Hours[$k] }
        $s
    }

    function Set-CacheEntry {
        # Legt einen Zwischenspeicher-Eintrag an, der vor -HoursAgo Stunden geholt wurde.
        param([string] $Service, [string] $Key, [string] $Content, [double] $HoursAgo)
        InModuleScope SoftwareInventory -Parameters @{ S = $Service; K = $Key; C = $Content; H = $HoursAgo } {
            $file = Get-ServiceCacheFile -Service $S -CacheKey $K
            New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force | Out-Null
            [pscustomobject] @{ FetchedAt = [datetime]::UtcNow.AddHours(-$H).ToString('o'); Content = $C } |
                ConvertTo-Json -Compress | Set-Content -LiteralPath $file -Encoding utf8NoBOM
            $file
        }
    }

    function Invoke-Request {
        # Eine Anfrage mit Mitschrieb; liefert @{ Output; Trace }.
        param([string] $Service, [string] $Key, $Setting)
        InModuleScope SoftwareInventory -Parameters @{ S = $Service; K = $Key; T = $Setting } {
            Invoke-WithCheckTrace { Invoke-ServiceRequest -Service $S -Uri "https://example.invalid/$K" -CacheKey $K -Setting $T }
        }
    }

    function New-TestRecord {
        param([string] $Name = 'Contoso Tool', [string] $Version = '1.0', [hashtable] $Property = @{})
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; V = $Version; P = $Property } {
            $p = @{ Version = $V; Publisher = 'Contoso' } + $P
            New-SoftwareRecord -Name $N -Source Registry -Property $p
        }
    }
}

Describe 'Zwischenspeicher für Online-Abfragen' {
    BeforeEach {
        $saved = $env:NVD_API_KEY
        $env:NVD_API_KEY = $null
        $cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Start-Sleep { }
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { [pscustomobject] @{ StatusCode = 200; Content = '{"neu":1}' } }
    }
    AfterEach { $env:NVD_API_KEY = $saved }

    It 'nimmt die Haltbarkeit je Quelle aus den Einstellungen' {
        $s = New-EnabledSetting GitHub, NVD -Hours @{ LatestVersion = 6; NVD = 24 }
        Set-CacheEntry GitHub 'repo' '{"alt":1}' 7 | Out-Null
        Set-CacheEntry NVD 'cpe' '{"alt":1}' 7 | Out-Null
        (Invoke-Request GitHub 'repo' $s).Output.neu | Should -Be 1   # 7 h > 6 h: neu geholt
        (Invoke-Request NVD 'cpe' $s).Output.alt | Should -Be 1       # 7 h < 24 h: aus dem Cache
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly
    }

    It 'holt bei Neu prüfen jede Antwort einmal je Lauf frisch' {
        $s = New-EnabledSetting KEV
        Set-CacheEntry KEV 'kev/catalog' '{"alt":1}' 1 | Out-Null
        $outputs = InModuleScope SoftwareInventory -Parameters @{ T = $s } {
            $owner = Enter-CacheRefresh
            try {
                1..2 | ForEach-Object { Invoke-ServiceRequest -Service KEV -Uri 'https://example.invalid/kev' -CacheKey 'kev/catalog' -Setting $T }
            }
            finally { Exit-CacheRefresh $owner }
        }
        $outputs.neu | Should -Be @(1, 1)
        Should -Invoke -ModuleName SoftwareInventory Invoke-WebRequest -Times 1 -Exactly
        InModuleScope SoftwareInventory { $script:CacheRefresh } | Should -BeNullOrEmpty
    }

    It 'nimmt offline den abgelaufenen Eintrag und kennzeichnet ihn als veraltet' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('Keine Verbindung') }
        $s = New-EnabledSetting NVD
        Set-CacheEntry NVD 'cpe' '{"alt":1}' 30 | Out-Null
        $r = Invoke-Request NVD 'cpe' $s
        $r.Output.alt | Should -Be 1
        $r.Trace.Stale | Should -Be @($true)
        $summary = InModuleScope SoftwareInventory -Parameters @{ T = $r.Trace } { Get-CheckTraceSummary $T }
        $summary.Stale | Should -BeTrue
        $summary.CheckedAt | Should -BeLessThan ([datetime]::UtcNow.AddHours(-29))
    }

    It 'wirft offline weiterhin, wenn es keinen Eintrag gibt' {
        Mock -ModuleName SoftwareInventory Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('Keine Verbindung') }
        { Invoke-Request NVD 'cpe' (New-EnabledSetting NVD) } | Should -Throw
    }

    It 'vermerkt frische Abrufe als nicht veraltet' {
        $r = Invoke-Request EPSS 'epss/x' (New-EnabledSetting EPSS)
        $r.Trace.Stale | Should -Be @($false)
        $r.Trace.FetchedAt | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-1))
    }
}

Describe 'Geprüft-Zeitpunkt der Prüfungen' {
    It 'setzt bei winget-Daten den Zeitpunkt des Scans und lässt ihn ohne Ergebnis leer' {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { InModuleScope SoftwareInventory { New-DefaultSetting } }
        Mock -ModuleName SoftwareInventory Get-SoftwareCatalog { @() }
        $withWinget = New-TestRecord -Property @{ WingetId = 'Contoso.Tool'; AvailableVersion = '2.0' } | Test-SoftwareUpdate
        $withWinget.CheckedAt | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-1))
        $withWinget.CheckStale | Should -BeFalse
        (New-TestRecord | Test-SoftwareUpdate).CheckedAt | Should -BeNullOrEmpty
    }

    It 'nimmt in der Ampel das Ältere und meldet veraltet, wenn eine Prüfung es ist' {
        $old = [datetime]::UtcNow.AddHours(-30)
        $new = [datetime]::UtcNow.AddHours(-1)
        $script:u = [pscustomobject] @{ Status = 'UpToDate'; InstalledVersion = '1.0'; LatestVersion = '1.0'; Source = 'Winget'; Confirmed = $true; Reason = $null; CheckedAt = $new; CheckStale = $false }
        $script:v = [pscustomobject] @{ Status = 'Checked'; Reason = $null; Vulnerabilities = @(); Cpe = @(); CpeSource = 'Catalog'; Notes = @(); CheckedAt = $old; CheckStale = $true }
        Mock -ModuleName SoftwareInventory Test-SoftwareUpdate { $script:u }
        Mock -ModuleName SoftwareInventory Get-SoftwareVulnerability { $script:v }
        $r = New-TestRecord | Get-SecurityRating
        $r.CheckedAt | Should -Be $old
        $r.UpdateCheckedAt | Should -Be $new
        $r.VulnerabilityCheckedAt | Should -Be $old
        $r.CheckStale | Should -BeTrue
    }
}

Describe 'Clear-CheckCache' {
    BeforeEach {
        $cache = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
    }

    It 'verwirft die Einträge eines Programms, aber nie den gemeinsamen KEV-Katalog' {
        $record = New-TestRecord
        $nvd = Set-CacheEntry NVD 'cpe' '{}' 1
        $github = Set-CacheEntry GitHub 'repo' '{}' 1
        $kev = Set-CacheEntry KEV 'kev/catalog' '{}' 1
        $other = Set-CacheEntry NVD 'anderes' '{}' 1
        InModuleScope SoftwareInventory -Parameters @{ R = $record; N = $nvd; K = $kev; G = $github } {
            # Auch wenn ein Mitschrieb den KEV-Katalog enthält, landet er nicht im Index und bleibt erhalten.
            Save-CheckIndex -Record $R -Kind Vulnerability -Trace @([pscustomobject] @{ Service = 'NVD'; File = $N }, [pscustomobject] @{ Service = 'KEV'; File = $K })
            Save-CheckIndex -Record $R -Kind Update -Trace @([pscustomobject] @{ Service = 'GitHub'; File = $G })
        }

        $record | Clear-CheckCache -Confirm:$false

        Test-Path $nvd | Should -BeFalse
        Test-Path $github | Should -BeFalse
        Test-Path $kev | Should -BeTrue
        Test-Path $other | Should -BeTrue
        InModuleScope SoftwareInventory -Parameters @{ R = $record } { Test-Path (Get-CheckIndexFile $R) } | Should -BeFalse
    }

    It 'führt je Version einen eigenen Index' {
        InModuleScope SoftwareInventory -Parameters @{ A = (New-TestRecord -Version '1.0'); B = (New-TestRecord -Version '2.0') } {
            Get-CheckIndexFile $A | Should -Not -Be (Get-CheckIndexFile $B)
        }
    }
}

Describe 'Get-RefreshEstimate' {
    BeforeEach {
        $saved = $env:NVD_API_KEY
        Mock -ModuleName SoftwareInventory Get-SoftwareCatalog { @() }
        Mock -ModuleName SoftwareInventory Read-CpeMapping { @{} }
        Mock -ModuleName SoftwareInventory Get-RecordCpe { @{ Cpe = @('cpe:2.3:a:contoso:tool'); Source = 'Catalog' } }
    }
    AfterEach { $env:NVD_API_KEY = $saved }

    It 'schätzt ohne NVD-Schlüssel 6 Sekunden je Anfrage und verlangt eine Bestätigung' {
        $env:NVD_API_KEY = $null
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting NVD }
        $e = 1..3 | ForEach-Object { New-TestRecord -Name "Tool $_" } | Get-RefreshEstimate
        $e.NvdRequests | Should -Be 3
        $e.Seconds | Should -Be 18
        $e.NeedsConfirmation | Should -BeTrue
    }

    It 'zählt CIRCL mit 3 Sekunden je Anfrage dazu, aber nur die längere Wartezeit' {
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting CIRCL }
        $e = 1..3 | ForEach-Object { New-TestRecord -Name "Tool $_" } | Get-RefreshEstimate
        $e.CirclRequests | Should -Be 3
        $e.NvdRequests | Should -Be 0
        $e.Seconds | Should -Be 9
        $e.NeedsConfirmation | Should -BeFalse

        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting NVD, CIRCL }
        # mit beiden Diensten je CPE zwei NVD-Anfragen (Versionssuche und Sammelabfrage für den Abgleich)
        $both = 1..3 | ForEach-Object { New-TestRecord -Name "Tool $_" } | Get-RefreshEstimate
        $both.NvdRequests | Should -Be 6
        $both.Seconds | Should -Be 36
    }

    It 'schätzt die CIRCL-Seiten aus dem Bestand und rechnet je CPE nacheinander' {
        $cache = Join-Path $TestDrive "$([guid]::NewGuid())\cache"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        # Bestand von 340 KB, also etwa 10 Seiten
        $store = InModuleScope SoftwareInventory { Get-CirclStoreFile -Vendor 'contoso' -Product 'tool' }
        New-Item -ItemType Directory -Path (Split-Path $store) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($store, [byte[]]::new(340KB))

        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting CIRCL }
        $e = New-TestRecord | Get-RefreshEstimate
        $e.CirclRequests | Should -Be 10
        $e.CirclUnknown | Should -Be 0
        $e.Seconds | Should -Be 30

        # Mit NVD: Versionssuche (6 s), dann 10 CIRCL-Seiten (30 s), der Abgleich wartet nicht mehr extra
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting NVD, CIRCL }
        $both = New-TestRecord | Get-RefreshEstimate
        $both.NvdRequests | Should -Be 2
        $both.Seconds | Should -Be 36
        $both.NeedsConfirmation | Should -BeTrue
        $both.ConfirmReason | Should -Be 'NvdWithoutKey'
    }

    It 'fragt auch mit Schlüssel nach, wenn es länger als 5 Minuten dauert' {
        $cache = Join-Path $TestDrive "$([guid]::NewGuid())\cache"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { 'test-schluessel' }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting NVD, CIRCL }
        # 250 Seiten mit 1,5 s Abstand (Schlüssel auch für CIRCL): gut 6 Minuten
        $store = InModuleScope SoftwareInventory { Get-CirclStoreFile -Vendor 'contoso' -Product 'tool' }
        New-Item -ItemType Directory -Path (Split-Path $store) -Force | Out-Null
        [System.IO.File]::WriteAllBytes($store, [byte[]]::new(250 * 34KB))
        $e = New-TestRecord | Get-RefreshEstimate
        $e.Seconds | Should -BeGreaterThan 300
        $e.NeedsConfirmation | Should -BeTrue
        $e.ConfirmReason | Should -Be 'LongDuration'
    }

    It 'nennt CPEs ohne Bestand, für die die Seitenzahl unbekannt ist' {
        $cache = Join-Path $TestDrive "$([guid]::NewGuid())\cache"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting CIRCL }
        $e = 1..2 | ForEach-Object { New-TestRecord -Name "Tool $_" } | Get-RefreshEstimate
        $e.CirclUnknown | Should -Be 2
        $e.CirclRequests | Should -Be 2

        $empty = Get-RefreshEstimate -InputObject @()
        $empty.Seconds | Should -Be 0
        $empty.CirclRequests | Should -Be 0
    }

    It 'fragt mit Schlüssel oder ohne aktivierte NVD nicht nach' {
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { 'nvd-test-123' }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting NVD }
        $e = 1..3 | ForEach-Object { New-TestRecord -Name "Tool $_" } | Get-RefreshEstimate
        $e.Seconds | Should -Be 2
        $e.NeedsConfirmation | Should -BeFalse

        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        Mock -ModuleName SoftwareInventory Read-InventorySetting { New-EnabledSetting }
        (New-TestRecord | Get-RefreshEstimate).NeedsConfirmation | Should -BeFalse
    }
}

Describe 'Einstellung CacheHours' {
    It 'hat die Standardwerte und übernimmt nur Werte zwischen 1 und 720' {
        $d = InModuleScope SoftwareInventory { New-DefaultSetting }
        $d.CacheHours.LatestVersion | Should -Be 6
        $d.CacheHours.NVD | Should -Be 24
        { Set-InventorySetting -CacheHoursNvd 0 -WhatIf } | Should -Throw
        { Set-InventorySetting -CacheHoursNvd 721 -WhatIf } | Should -Throw
    }
}
