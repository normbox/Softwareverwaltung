BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-Vuln {
        param([string] $Id = 'CVE-2026-0001', [string] $Assessment = 'Affected', [double] $Score = 7.0, [switch] $Kev, $Note)
        [pscustomobject] @{ CveId = $Id; Assessment = $Assessment; Score = $Score; Kev = [bool] $Kev; Note = $Note; Epss = 0.12; Published = '2026-01-01T00:00:00.000'
            Url = "https://nvd.nist.gov/vuln/detail/$Id"; Description = 'Beschreibung'; KevDateAdded = $null; KevRansomware = $false }
    }
    function New-VulnStatus {
        param([string] $Status = 'Checked', [object[]] $Vulns = @(), $Reason)
        [pscustomobject] @{ Status = $Status; Reason = $Reason; Vulnerabilities = @($Vulns); Cpe = @('cpe:2.3:a:x:y:1.0:*:*:*:*:*:*:*'); CpeSource = 'Catalog'; Notes = @() }
    }
    function New-UpdateStatus {
        param([string] $Status = 'UpToDate', [string] $Latest = '1.0', [bool] $Confirmed = $true, $Reason, [string] $Source = 'Winget')
        [pscustomobject] @{ Status = $Status; InstalledVersion = '1.0'; LatestVersion = $Latest; Source = $Source; Confirmed = $Confirmed; Reason = $Reason }
    }
    function Get-Rating { param($U, $V) InModuleScope SoftwareInventory -Parameters @{ U = $U; V = $V } { Get-RatingFromResult -UpdateStatus $U -VulnerabilityStatus $V } }
    function New-Msg {
        param([string] $Code, [object[]] $Arguments = @())
        InModuleScope SoftwareInventory -Parameters @{ C = $Code; A = $Arguments } { New-InventoryMessage $C $A }
    }
}

Describe 'Ampelregeln' {
    It 'Rot bei aktiv ausgenutzter Lücke' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Kev -Score 6))
        $r.Rating | Should -Be 'Red'
        $r.Reasons[0].Code | Should -Be 'KevAffected'
        $r.Reasons[0].Args | Should -Be @('CVE-2026-0001')
        $r.Reasons[0].Text | Should -Match 'Aktiv ausgenutzte Lücke CVE-2026-0001'
    }

    It 'Rot bei kritischer Lücke (CVSS ab 9)' {
        (Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Score 9.0))).Rating | Should -Be 'Red'
    }

    It 'Gelb bei anderen Lücken mit Anzahl und höchstem CVSS' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @((New-Vuln -Score 7.5), (New-Vuln -Id 'CVE-2026-0002' -Score 4.0)))
        $r.Rating | Should -Be 'Yellow'
        $r.Reasons.Code | Should -Contain 'KnownVulnerabilitiesMaxCvss'
        ($r.Reasons | Where-Object Code -EQ 'KnownVulnerabilitiesMaxCvss').Args | Should -Be @(2, 7.5)
    }

    It 'nennt <Case> in Ein- oder Mehrzahl' -ForEach @(
        @{ Case = 'eine Lücke mit CVE'; Scores = @(7.5); Code = 'KnownVulnerabilitiesMaxCvss'; Text = 'Bekannte Lücke CVE-2026-0101 (CVSS 7.5)' }
        @{ Case = 'mehrere Lücken'; Scores = @(7.5, 4.0); Code = 'KnownVulnerabilitiesMaxCvss'; Text = '2 bekannte Lücken, höchster CVSS 7.5' }
        @{ Case = 'eine weitere Lücke neben einer kritischen'; Scores = @(9.8, 8.7); Code = 'OtherVulnerabilitiesMaxCvss'; Text = 'Weitere Lücke CVE-2026-0102 (CVSS 8.7)' }
        @{ Case = 'mehrere weitere Lücken neben einer kritischen'; Scores = @(9.8, 8.7, 5.0); Code = 'OtherVulnerabilitiesMaxCvss'; Text = '2 weitere Lücken, höchster CVSS 8.7' }
    ) {
        $i = 100
        $vulns = foreach ($s in $Scores) { $i++; New-Vuln -Id "CVE-2026-0$i" -Score $s }
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @($vulns))
        $reason = $r.Reasons | Where-Object Code -EQ $Code
        $reason.Text | Should -Be $Text
        $reason.Args[0] | Should -Be @($Scores | Where-Object { $_ -lt 9 }).Count
    }

    It 'nennt eine Lücke ohne CVSS mit ihrer CVE' {
        $v = New-Vuln -Id 'CVE-2026-0200'
        $v.Score = $null
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @($v))
        ($r.Reasons | Where-Object Code -EQ 'KnownVulnerabilities').Text | Should -Be 'Bekannte Lücke CVE-2026-0200'
    }

    It 'fasst mehrere „möglicherweise betroffen“ zu einem Grund zusammen, KEV bleibt einzeln' {
        $note = New-Msg CirclNoVersionRange
        $vulns = @(
            (New-Vuln 'CVE-2026-0301' -Assessment PossiblyAffected -Note $note)
            (New-Vuln 'CVE-2026-0302' -Assessment PossiblyAffected -Note $note)
            (New-Vuln 'CVE-2026-0303' -Assessment PossiblyAffected -Note $note)
            (New-Vuln 'CVE-2026-0304' -Assessment PossiblyAffected -Kev -Note (New-Msg KevNvdNoVersionData))
        )
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns $vulns)
        $r.Reasons.Code | Should -Be @('PossiblyAffectedKev', 'PossiblyAffectedCount')
        $count = $r.Reasons | Where-Object Code -EQ 'PossiblyAffectedCount'
        $count.Args[0] | Should -Be 3
        $count.Text | Should -Be "3 Lücken möglicherweise betroffen ($($note.Text))"

        # Verschiedene Gründe: allgemeiner Hinweis; eine einzelne bleibt wie bisher mit CVE
        $mixed = @((New-Vuln 'CVE-2026-0305' -Assessment PossiblyAffected -Note $note), (New-Vuln 'CVE-2026-0306' -Assessment PossiblyAffected -Note (New-Msg NvdNoVersionRange)))
        (Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns $mixed)).Reasons[0].Text | Should -Be '2 Lücken möglicherweise betroffen (verschiedene Gründe, siehe Lücken)'
        (Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @($mixed[0]))).Reasons[0].Code | Should -Be 'PossiblyAffected'
    }

    It 'Gelb (nicht Rot) bei KEV-Eintrag, dessen Version nicht prüfbar ist' {
        $possible = New-Vuln -Assessment PossiblyAffected -Kev -Score 9.8 -Note (New-Msg KevNvdNoVersionData)
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @($possible))
        $r.Rating | Should -Be 'Yellow'
        $r.Reasons[0].Code | Should -Be 'PossiblyAffectedKev'
        $r.Reasons[0].Args[1].Code | Should -Be 'KevNvdNoVersionData'
        # Verschachtelte Meldung geht mit ihrem Text in den Text ein.
        $r.Reasons[0].Text | Should -Be 'Möglicherweise betroffen: CVE-2026-0001 (aktiv ausgenutzt, Version nicht prüfbar (NVD ohne Versionsdaten))'
    }

    It 'Gelb bei verfügbarem Update, unbestätigte Quelle gekennzeichnet' {
        $r = Get-Rating (New-UpdateStatus -Status Outdated -Latest '2.0' -Confirmed $false -Source WingetSearch) (New-VulnStatus -Status Unknown -Reason (New-Msg NoCpe))
        $r.Rating | Should -Be 'Yellow'
        $update = $r.Reasons | Where-Object Code -EQ 'UpdateAvailableUnconfirmed'
        $update.Args | Should -Be @('1.0', '2.0', 'WingetSearch')
        $update.Text | Should -Be 'Update verfügbar: 1.0 → 2.0 (Quelle WingetSearch, unbestätigt)'
    }

    It 'Grün nur nach gelaufener Sicherheitsprüfung, Hinweise färben nicht' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Assessment Informational -Score 10))
        $r.Rating | Should -Be 'Green'
        $r.Reasons.Code | Should -Be @('NoFindings', 'VersionCurrent')
    }

    It 'Grau statt Gelb, wenn der einzige KEV-Treffer ohne NVD widerlegt ist, und nennt die Widerlegung' {
        $v = New-VulnStatus -Status Unknown -Reason (New-Msg ServiceDisabled 'NVD')
        $v | Add-Member Refuted @([pscustomobject] @{ CveId = 'CVE-2025-0411'; Source = 'Catalog'; Note = (New-Msg KevRefutedCatalog 'CVE-2025-0411', '24.09', '26.05') })
        $r = Get-Rating (New-UpdateStatus) $v
        $r.Rating | Should -Be 'Gray'
        $r.Reasons.Code | Should -Be @('NotCheckedBecause', 'KevRefutedCatalog', 'VersionCurrent')
        $r.Reasons[0].Args[0].Code | Should -Be 'ServiceDisabled'
        $r.Reasons[0].Text | Should -Be 'Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert'
    }

    It 'Grün mit Widerlegung als Grund, wenn NVD geprüft hat' {
        $v = New-VulnStatus
        $v | Add-Member Refuted @([pscustomobject] @{ CveId = 'CVE-2025-0411'; Source = 'NVD'; Note = (New-Msg KevRefutedNvd 'CVE-2025-0411', '26.05') })
        $r = Get-Rating (New-UpdateStatus) $v
        $r.Rating | Should -Be 'Green'
        $r.Reasons.Code | Should -Contain 'KevRefutedNvd'
    }

    It 'jedes Gelb hat einen Grund' {
        foreach ($case in @(
                @{ U = (New-UpdateStatus); V = (New-VulnStatus -Vulns @(New-Vuln -Assessment PossiblyAffected -Kev -Note (New-Msg KevNvdDisabled))) }
                @{ U = (New-UpdateStatus); V = (New-VulnStatus -Vulns @(New-Vuln -Score 5)) }
                @{ U = (New-UpdateStatus -Status Outdated -Latest '2.0'); V = (New-VulnStatus -Status Unknown -Reason (New-Msg NoCpe)) }
            )) {
            $r = Get-Rating $case.U $case.V
            $r.Rating | Should -Be 'Yellow'
            @($r.Reasons | Where-Object { $_.Code -and $_.Text }).Count | Should -BeGreaterThan 0
        }
    }

    It 'Grau mit Grund, auch wenn die Version aktuell ist' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Status Unknown -Reason (New-Msg ServiceDisabled 'NVD'))
        $r.Rating | Should -Be 'Gray'
        $r.Reasons.Code | Should -Be @('NotCheckedBecause', 'VersionCurrent')
    }

    It 'Grau nennt den Grund der fehlenden Prüfung und den unbekannten Versionsstand' {
        $r = Get-Rating (New-UpdateStatus -Status Unknown -Latest $null -Reason (New-Msg ServiceDisabled 'GitHub')) (New-VulnStatus -Status Unknown -Reason (New-Msg NoCpe))
        $r.Rating | Should -Be 'Gray'
        $r.Reasons.Code | Should -Be @('NotCheckedBecause', 'VersionUnknownBecause')
        $r.Reasons[0].Args[0].Code | Should -Be 'NoCpe'
        $r.Reasons[1].Args[0].Code | Should -Be 'ServiceDisabled'
        $r.Reasons[1].Args[0].Args | Should -Be @('GitHub')
    }
}

Describe 'Get-SecurityRating' {
    It 'verbindet Update- und Schwachstellenstatus je Programm und sortiert nach Dringlichkeit' {
        Mock -ModuleName SoftwareInventory Test-SoftwareUpdate {
            New-UpdateStatus; New-UpdateStatus -Status Outdated -Latest '2.0'; New-UpdateStatus
        }
        Mock -ModuleName SoftwareInventory Get-SoftwareVulnerability {
            New-VulnStatus; New-VulnStatus -Status Unknown -Reason 'Keine CPE'; New-VulnStatus -Vulns @(New-Vuln -Kev)
        }
        $records = InModuleScope SoftwareInventory { 'A-Grün', 'B-Gelb', 'C-Rot' | ForEach-Object { New-SoftwareRecord -Name $_ -Source Registry -Property @{ Version = '1.0' } } }
        $r = @($records | Get-SecurityRating)
        $r.Name | Should -Be @('C-Rot', 'B-Gelb', 'A-Grün')
        $r.Rating | Should -Be @('Red', 'Yellow', 'Green')
        $r[1].LatestVersion | Should -Be '2.0'
        Should -Invoke -ModuleName SoftwareInventory Test-SoftwareUpdate -Times 1 -Exactly
    }
}

Describe 'Export-SecurityReport' {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Read-InventorySetting { $s = InModuleScope SoftwareInventory { New-DefaultSetting }; $s.Services.NVD = $true; $s }
        $record = InModuleScope SoftwareInventory {
            New-SoftwareRecord -Name 'Tool <script>alert(1)</script>' -Source Portable -Property @{ Version = '1.0'; FilePath = "$env:USERPROFILE\Downloads\tool.exe" }
        }
        $rating = [pscustomobject] @{
            PSTypeName = 'SoftwareInventory.SecurityRating'; Name = $record.Name; Version = '1.0'; Rating = 'Red'
            Reasons = @("Aktiv ausgenutzte Lücke CVE-2026-0001 (CISA KEV) auf $env:COMPUTERNAME"); LatestVersion = '2.0'
            UpdateStatus = (New-UpdateStatus -Status Outdated -Latest '2.0' -Confirmed $false); VulnerabilityStatus = (New-VulnStatus -Vulns @((New-Vuln -Kev), (New-Vuln -Id 'CVE-2007-0001' -Assessment Informational)))
            Record = $record
        }
        $file = $rating | Export-SecurityReport -Path (Join-Path $TestDrive 'bericht\bericht.html')
        $html = Get-Content $file.FullName -Raw
    }

    It 'schreibt eine eigenständige HTML-Datei' {
        $file.Name | Should -Be 'bericht.html'
        $html | Should -Match '<!DOCTYPE html>'
        $html | Should -Not -Match '<script src=|<link '
    }

    It 'nennt im Bericht die Angabe jeder Quelle mit Namensnennung' {
        $vuln = New-Vuln -Id 'CVE-2026-0002'
        $sources = InModuleScope SoftwareInventory {
            @((New-SourceStatement -Source NVD -Verdict Affected -CveId 'CVE-2026-0002' -Range '< 2.0'),
                (New-SourceStatement -Source CIRCL -Verdict NotAffected -CveId 'CVE-2026-0002' -Range '< 1.0'))
        }
        $vuln | Add-Member Sources $sources
        $r = $rating.PSObject.Copy()
        $r.VulnerabilityStatus = New-VulnStatus -Vulns @($vuln)
        $f = $r | Export-SecurityReport -Path (Join-Path $TestDrive 'quellen.html')
        $text = Get-Content $f.FullName -Raw
        $text | Should -Match 'NVD: betroffen \(&lt; 2\.0\)'
        $text | Should -Match 'CIRCL: nicht betroffen \(&lt; 1\.0\) · Daten: CVE-Programm (über|&#252;ber) CIRCL, CC BY 4\.0'
    }

    It 'maskiert Werte als HTML' {
        $html | Should -Match 'Tool &lt;script&gt;alert\(1\)&lt;/script&gt;'
        $html | Should -Not -Match '<script>alert'
    }

    It 'ersetzt Benutzerprofil und Rechnername' {
        $html | Should -Match '%USERPROFILE%\\Downloads\\tool.exe'
        $html | Should -Not -Match ([regex]::Escape($env:USERPROFILE))
        $html | Should -Not -Match "\b$([regex]::Escape($env:COMPUTERNAME))\b"
    }

    It 'zeigt Ampel, Zählung, Filter, CVE-Links und Kennzeichnungen' {
        $html | Should -Match "<span class='badge red'>Rot</span>"
        $html | Should -Match 'data-filter="update"'
        $html | Should -Match "data-update='true' data-risk='true'"
        $html | Should -Match "href='https://nvd.nist.gov/vuln/detail/CVE-2026-0001'"
        $html | Should -Match 'unbestätigt'
        $html | Should -Match "<tr class='info'>"
        $html | Should -Match 'Aktivierte Dienste: NVD'
    }

    It 'berechnet die Ampel selbst, wenn Datensätze übergeben werden' {
        Mock -ModuleName SoftwareInventory Get-SecurityRating { $rating }
        $plain = InModuleScope SoftwareInventory { New-SoftwareRecord -Name 'Plain' -Source Registry -Property @{ Version = '1.0' } }
        $f = $plain | Export-SecurityReport -Path (Join-Path $TestDrive 'b2.html')
        Should -Invoke -ModuleName SoftwareInventory Get-SecurityRating -Times 1 -Exactly
        Get-Content $f.FullName -Raw | Should -Match 'Tool &lt;script'
    }
}
