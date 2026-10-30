BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function Start-TestProgress {
        # Laufende Anzeige wie während einer Sicherheitsprüfung
        InModuleScope SoftwareInventory { Write-CheckProgress -Id 4 -Activity ProgressCheckVulnerabilities -Index 3 -Total 9 -Name 'Google Chrome' }
    }
    function Get-Operation {
        # Alle gemeldeten zweiten Zeilen in Reihenfolge
        @($script:Operations)
    }
}

Describe 'Write-CheckStep' {
    BeforeEach {
        $script:Operations = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName SoftwareInventory Write-Progress { if ($CurrentOperation) { $script:Operations.Add($CurrentOperation) } }
    }
    AfterEach { InModuleScope SoftwareInventory { $script:CheckProgress = $null; $script:CheckStep = $null } }

    It 'setzt die zweite Zeile der laufenden Anzeige, ohne Tätigkeit und Programm zu ändern' {
        Start-TestProgress
        InModuleScope SoftwareInventory { Write-CheckStep -Key StepNvdVersionSearch }
        Get-Operation | Should -Be @('NVD: Versionssuche')
        Should -Invoke -ModuleName SoftwareInventory Write-Progress -Times 1 -Exactly -ParameterFilter {
            $CurrentOperation -eq 'NVD: Versionssuche' -and $Activity -eq 'Prüfe Sicherheitslücken (3 von 9)' -and $Status -eq 'Google Chrome' -and $Id -eq 4
        }
    }

    It 'hängt eine Wartezeit an den aktuellen Schritt, statt ihn zu ersetzen' {
        Start-TestProgress
        InModuleScope SoftwareInventory {
            Write-CheckStep -Key StepCirclFullCounted -Arguments 37, 149, 'noch etwa 6 Min.'
            Write-CheckStep -Key StepWaitInterval -Arguments 3, 'CIRCL' -Wait
            Write-CheckStep -Key StepWaitInterval -Arguments 2, 'CIRCL' -Wait
        }
        Get-Operation | Should -Be @(
            'CIRCL: vollständiger Abruf, Seite 37 von 149, noch etwa 6 Min.'
            'CIRCL: vollständiger Abruf, Seite 37 von 149, noch etwa 6 Min. · Warte 3 s (Anfragelimit CIRCL)'
            'CIRCL: vollständiger Abruf, Seite 37 von 149, noch etwa 6 Min. · Warte 2 s (Anfragelimit CIRCL)'
        )
    }

    It 'meldet nichts ohne laufende Anzeige und nach deren Ende' {
        InModuleScope SoftwareInventory { Write-CheckStep -Key StepNvdVersionSearch }
        Start-TestProgress
        InModuleScope SoftwareInventory {
            Write-CheckProgress -Id 4 -Activity ProgressCheckVulnerabilities -Completed
            Write-CheckStep -Key StepNvdVersionSearch
        }
        Get-Operation | Should -BeNullOrEmpty
    }

    It 'nennt die Restzeit grob: <Seconds> s → <Expected>' -ForEach @(
        @{ Seconds = 20; Expected = 'noch unter 1 Min.' }
        @{ Seconds = 61; Expected = 'noch etwa 2 Min.' }
        @{ Seconds = 360; Expected = 'noch etwa 6 Min.' }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ S = $Seconds } { Format-RemainingTime $S } | Should -Be $Expected
    }

    It 'hat für jeden Schritt einen Text, auch mit Seitenzahl' {
        $root = Join-Path $PSScriptRoot '../../src/SoftwareInventory'
        $used = Get-ChildItem $root -Recurse -Filter '*.ps1' | Select-String -Pattern "Step\w+" -AllMatches |
            ForEach-Object { $_.Matches.Value } | Where-Object { $_ -cmatch '^Step[A-Z]' } | Sort-Object -Unique
        $strings = InModuleScope SoftwareInventory { $script:Strings }
        $used | Should -Not -BeNullOrEmpty
        foreach ($key in $used) { $strings.ContainsKey($key) | Should -BeTrue -Because "Schritt '$key' wird im Code verwendet" }
        foreach ($key in 'StepCirclFirst', 'StepCirclFull', 'StepNvdVersionSearch', 'StepNvdCompare') { $strings.ContainsKey("${key}Counted") | Should -BeTrue }
    }
}

Describe 'Fortschritt bei den Abfragen' {
    BeforeEach {
        $script:Operations = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName SoftwareInventory Write-Progress { if ($CurrentOperation) { $script:Operations.Add($CurrentOperation) } }
        Mock -ModuleName SoftwareInventory Start-Sleep { }
        $cache = Join-Path $TestDrive "$([guid]::NewGuid())\cache"
        Mock -ModuleName SoftwareInventory Get-CacheDirectory { $cache }
        Start-TestProgress
    }
    AfterEach { InModuleScope SoftwareInventory { $script:CheckProgress = $null; $script:CheckStep = $null; $script:LastServiceCall = @{} } }

    It 'zeigt beim ersten CIRCL-Abruf Seite x von y mit Restzeit und den Hinweis auf den Zwischenspeicher' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            $page = [int] ([regex]::Match("$Uri", '&page=(\d+)').Groups[1].Value)
            $rows = @(1..100 | ForEach-Object { , @("cve-2026-$page$_", @{ cveMetadata = @{ cveId = "CVE-2026-$page$('{0:d3}' -f $_)" }; containers = @{ cna = @{} } }) })
            @{ results = @{ cvelistv5 = $rows }; total_count = 300 } | ConvertTo-Json -Depth 8 | ConvertFrom-Json -DateKind String
        }
        InModuleScope SoftwareInventory { Get-CirclCve -CpeBase 'cpe:2.3:a:google:chrome' -Setting $null } | Out-Null
        $ops = Get-Operation
        $ops[0] | Should -BeLike 'CIRCL: erster Abruf, bei Produkten mit vielen Lücken einige Minuten*'
        $ops[1] | Should -Match '^CIRCL: erster Abruf, Seite 2 von 3, noch (etwa \d+|unter 1) Min\. \(danach aus dem Zwischenspeicher\)$'
        $ops[2] | Should -Match '^CIRCL: erster Abruf, Seite 3 von 3, '

        # Danach frisch: aus dem Zwischenspeicher
        $script:Operations.Clear()
        InModuleScope SoftwareInventory { Get-CirclCve -CpeBase 'cpe:2.3:a:google:chrome' -Setting $null } | Out-Null
        Get-Operation | Should -Be @('CIRCL: aus dem Zwischenspeicher')
    }

    It 'nennt beim Nachladen das Datum des letzten Abrufs und die Seite' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest { [pscustomobject] @{ cvelistv5 = @() } }
        $since = [datetime]::new(2026, 10, 29, 8, 0, 0, [DateTimeKind]::Utc)
        InModuleScope SoftwareInventory -Parameters @{ D = $since } { Get-CirclPage -Vendor 'google' -Product 'chrome' -Since $D -Setting $null } | Out-Null
        Get-Operation | Should -Be @("CIRCL: Änderungen seit $($since.ToLocalTime().ToString('d')), Seite 1")
    }

    It 'zeigt beim NVD-Abgleich ab Seite 2 die Seitenzahl' {
        Mock -ModuleName SoftwareInventory Invoke-ServiceRequest {
            $start = [int] ([regex]::Match("$Uri", 'startIndex=(\d+)').Groups[1].Value)
            [pscustomobject] @{ totalResults = 4500; resultsPerPage = 2000; startIndex = $start; vulnerabilities = @() }
        }
        InModuleScope SoftwareInventory { Get-NvdProductCve -CpeBase 'cpe:2.3:a:google:chrome' -Setting $null } | Out-Null
        Get-Operation | Should -Be @('NVD: Abgleich mit CIRCL', 'NVD: Abgleich mit CIRCL, Seite 2 von 3', 'NVD: Abgleich mit CIRCL, Seite 3 von 3')
    }

    It 'hängt die Wartezeit des Anfragelimits an und zeigt das Warten bei 429 in eigener Zeile' {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.CIRCL = $true; $s }
        Mock -ModuleName SoftwareInventory Get-ServiceSecret { $null }
        $script:Attempt = 0
        Mock -ModuleName SoftwareInventory Invoke-WebRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) {
                $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $response.Headers.RetryAfter = [System.Net.Http.Headers.RetryConditionHeaderValue]::new([timespan]::FromSeconds(30))
                $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('429', $response)
                throw [System.Management.Automation.ErrorRecord]::new($exception, 'WebCmdletWebResponseException', 'InvalidOperation', $null)
            }
            [pscustomobject] @{ StatusCode = 200; Content = '{"ok":1}' }
        }
        InModuleScope SoftwareInventory {
            Write-CheckStep -Key StepCirclFull
            # Letzte Anfrage gerade eben: Abstand von 3 s abwarten
            $script:LastServiceCall['CIRCL'] = [datetime]::UtcNow
            Invoke-ServiceRequest -Service CIRCL -Uri 'https://vulnerability.circl.lu/api/x' | Out-Null
        }
        $ops = Get-Operation
        $ops[0] | Should -Be 'CIRCL: vollständiger Abruf'
        $ops[1] | Should -Match '^CIRCL: vollständiger Abruf · Warte [23] s \(Anfragelimit CIRCL\)$'
        $ops | Should -Contain 'CIRCL: Warte 30 s (Dienst meldet Anfragelimit)'
    }
}
