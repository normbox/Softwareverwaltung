BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-Vuln {
        param([string] $Id = 'CVE-2026-0001', [string] $Assessment = 'Affected', [double] $Score = 7.0, [switch] $Kev, [string] $Note)
        [pscustomobject] @{ CveId = $Id; Assessment = $Assessment; Score = $Score; Kev = [bool] $Kev; Note = $Note; Epss = 0.12; Published = '2026-01-01T00:00:00.000'
            Url = "https://nvd.nist.gov/vuln/detail/$Id"; Description = 'Beschreibung'; KevDateAdded = $null; KevRansomware = $false }
    }
    function New-VulnStatus {
        param([string] $Status = 'Checked', [object[]] $Vulns = @(), [string] $Reason)
        [pscustomobject] @{ Status = $Status; Reason = $Reason; Vulnerabilities = @($Vulns); Cpe = @('cpe:2.3:a:x:y:1.0:*:*:*:*:*:*:*'); CpeSource = 'Catalog'; Notes = @() }
    }
    function New-UpdateStatus {
        param([string] $Status = 'UpToDate', [string] $Latest = '1.0', [bool] $Confirmed = $true, [string] $Reason, [string] $Source = 'Winget')
        [pscustomobject] @{ Status = $Status; InstalledVersion = '1.0'; LatestVersion = $Latest; Source = $Source; Confirmed = $Confirmed; Reason = $Reason }
    }
    function Get-Rating { param($U, $V) InModuleScope SoftwareInventory -Parameters @{ U = $U; V = $V } { Get-RatingFromResult -UpdateStatus $U -VulnerabilityStatus $V } }
}

Describe 'Ampelregeln' {
    It 'Rot bei aktiv ausgenutzter Lücke' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Kev -Score 6))
        $r.Rating | Should -Be 'Red'
        $r.Reasons[0] | Should -Match 'Aktiv ausgenutzte Lücke CVE-2026-0001'
    }

    It 'Rot bei kritischer Lücke (CVSS ab 9)' {
        (Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Score 9.0))).Rating | Should -Be 'Red'
    }

    It 'Gelb bei anderen Lücken mit Anzahl und höchstem CVSS' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @((New-Vuln -Score 7.5), (New-Vuln -Id 'CVE-2026-0002' -Score 4.0)))
        $r.Rating | Should -Be 'Yellow'
        $r.Reasons | Should -Contain '2 bekannte Lücke(n), höchster CVSS 7.5'
    }

    It 'Gelb (nicht Rot) bei KEV-Eintrag, dessen Version nicht prüfbar ist' {
        $possible = New-Vuln -Assessment PossiblyAffected -Kev -Score 9.8 -Note 'Aktiv ausgenutzt; Version nicht prüfbar (NVD ohne Versionsdaten)'
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @($possible))
        $r.Rating | Should -Be 'Yellow'
        $r.Reasons[0] | Should -Be 'Möglicherweise betroffen: CVE-2026-0001 (aktiv ausgenutzt, Version nicht prüfbar (NVD ohne Versionsdaten))'
    }

    It 'Gelb bei verfügbarem Update, unbestätigte Quelle gekennzeichnet' {
        $r = Get-Rating (New-UpdateStatus -Status Outdated -Latest '2.0' -Confirmed $false -Source WingetSearch) (New-VulnStatus -Status Unknown -Reason 'Keine CPE zugeordnet')
        $r.Rating | Should -Be 'Yellow'
        $r.Reasons | Should -Contain 'Update verfügbar: 1.0 → 2.0 (Quelle WingetSearch, unbestätigt)'
    }

    It 'Grün nur nach gelaufener Sicherheitsprüfung, Hinweise färben nicht' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Vulns @(New-Vuln -Assessment Informational -Score 10))
        $r.Rating | Should -Be 'Green'
        $r.Reasons | Should -Be @('Sicherheitsprüfung ohne Befund', 'Version aktuell')
    }

    It 'Grau mit Grund, auch wenn die Version aktuell ist' {
        $r = Get-Rating (New-UpdateStatus) (New-VulnStatus -Status Unknown -Reason 'Dienst NVD nicht aktiviert')
        $r.Rating | Should -Be 'Gray'
        $r.Reasons | Should -Be @('Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert', 'Version aktuell')
    }

    It 'Grau nennt den Grund der fehlenden Prüfung und den unbekannten Versionsstand' {
        $r = Get-Rating (New-UpdateStatus -Status Unknown -Latest $null -Reason 'Dienst GitHub nicht aktiviert') (New-VulnStatus -Status Unknown -Reason 'Keine CPE zugeordnet')
        $r.Rating | Should -Be 'Gray'
        $r.Reasons | Should -Be @('Nicht auf Lücken geprüft: Keine CPE zugeordnet', 'Versionsstand unbekannt: Dienst GitHub nicht aktiviert')
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
