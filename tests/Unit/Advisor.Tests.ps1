BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-TestRating {
        param([string] $Name, [string] $Rating, [hashtable] $Property, [string] $UpdateStatus = 'UpToDate', [object[]] $Vulns = @(), [string] $VulnStatus = 'Checked', [string[]] $Reasons = @('Grund'))
        $record = InModuleScope SoftwareInventory -Parameters @{ N = $Name; P = $Property } { New-SoftwareRecord -Name $N -Source Registry -Property $P }
        [pscustomobject] @{
            Name                = $Name
            Version             = $Property.Version
            Rating              = $Rating
            Reasons             = $Reasons
            LatestVersion       = '9.0'
            UpdateStatus        = [pscustomobject] @{ Status = $UpdateStatus; InstalledVersion = $Property.Version; LatestVersion = '9.0'; Source = 'Winget'; Confirmed = $true; Reason = $null }
            VulnerabilityStatus = [pscustomobject] @{ Status = $VulnStatus; Reason = $null; Notes = @(); Vulnerabilities = @($Vulns); Refuted = @() }
            Record              = $record
        }
    }

    function Invoke-Tool { param($Name, $Arguments = '{}') Invoke-AdvisorTool -Name $Name -ArgumentsJson $Arguments }
    function Get-Content2 { param($Result) $Result.Content | ConvertFrom-Json -AsHashtable }
}

Describe 'KI-Berater: Tools' {
    BeforeEach {
        Mock -ModuleName SoftwareInventory Get-PrivateIdentity {
            [pscustomobject] @{ UserProfile = 'C:\Users\normb'; UserName = 'normb'; ComputerName = 'NORM-PC'; Domain = 'NORM-PC' }
        }
        $script:ratings = @(
            New-TestRating 'Old Tool' Red @{ Version = '1.0'; Publisher = 'Contoso'; RegistryKey = 'HKLM:\X\Old'; InstallLocation = 'C:\Users\normb\Tools\Old' } -UpdateStatus Outdated `
                -Vulns @([pscustomobject] @{ CveId = 'CVE-2026-0001'; Assessment = 'Affected'; Kev = $true; Score = 9.8; Epss = 0.5; Note = $null; Description = 'Lücke in C:\Users\normb\x' }) `
                -Reasons @('Aktiv ausgenutzte Lücke CVE-2026-0001 (CISA KEV)', 'Update verfügbar')
            New-TestRating '7-Zip 26.05 (x64)' Gray @{ Version = '26.05'; Publisher = 'Igor Pavlov'; RegistryKey = 'HKLM:\X\7zip'; WingetId = '7zip.7zip' } -VulnStatus Unknown
            New-TestRating 'Firefox' Green @{ Version = '140.0'; Publisher = 'Mozilla'; RegistryKey = 'HKLM:\X\Firefox' }
        )
        Set-AdvisorContext -Rating $script:ratings
        $script:oldId = InModuleScope SoftwareInventory -Parameters @{ R = $script:ratings[0].Record } { Get-AdvisorProgramId $R }
        $script:zipId = InModuleScope SoftwareInventory -Parameters @{ R = $script:ratings[1].Record } { Get-AdvisorProgramId $R }
    }
    AfterAll { Set-AdvisorContext -Clear }

    It 'beschreibt alle Tools mit gültigem JSON-Schema und eine Systemanweisung' {
        $tools = Get-AdvisorTool
        $tools.Name | Should -Be @('get_inventory', 'get_program_details', 'check_latest_version', 'search_vulnerabilities', 'propose_update', 'propose_uninstall')
        foreach ($t in $tools) {
            $schema = $t.ParametersJson | ConvertFrom-Json -AsHashtable
            $schema.type | Should -Be 'object'
            $t.Description | Should -Not -BeNullOrEmpty
        }
        ($tools | Where-Object Kind -eq Proposal).Name | Should -Be @('propose_update', 'propose_uninstall')
        Get-AdvisorTool -SystemPrompt | Should -Match 'führst nie etwas aus'
    }

    It 'listet Programme nach Ampel sortiert mit kurzer neutraler id' {
        $r = Invoke-Tool get_inventory
        $r.Ok | Should -BeTrue
        $data = Get-Content2 $r
        $data.programs_in_scan | Should -Be 3
        $data.programs[0].name | Should -Be 'Old Tool'
        $data.programs[0].id | Should -Match '^p-[0-9a-f]{12}$'
        $data.programs[0].vulnerabilities | Should -Be 1
        $data.programs[1].vulnerabilities | Should -BeNullOrEmpty   # nicht geprüft
    }

    It 'filtert nach Name, Ampel, Updates und begrenzt die Anzahl' {
        (Get-Content2 (Invoke-Tool get_inventory '{"filter":"mozilla"}')).programs.name | Should -Be @('Firefox')
        (Get-Content2 (Invoke-Tool get_inventory '{"rating":"Red"}')).programs.name | Should -Be @('Old Tool')
        (Get-Content2 (Invoke-Tool get_inventory '{"updates_only":true}')).programs.name | Should -Be @('Old Tool')
        $limited = Get-Content2 (Invoke-Tool get_inventory '{"limit":1}')
        $limited.returned | Should -Be 1
        $limited.matching | Should -Be 3
    }

    It 'liefert Details und entfernt dabei persönliche Angaben' {
        $r = Invoke-Tool get_program_details "{`"id`":`"$oldId`"}"
        $r.Ok | Should -BeTrue
        $r.Content | Should -Not -Match 'normb'
        $r.Content | Should -Match '%USERPROFILE%'
        $data = Get-Content2 $r
        $data.vulnerability_list[0].cve | Should -Be 'CVE-2026-0001'
        $data.vulnerability_list[0].kev | Should -BeTrue
        $data.reasons.Count | Should -Be 2
    }

    It 'meldet Fehler mit festem Code und Meldung statt zu werfen: <Code>' -TestCases @(
        @{ Code = 'UnknownTool'; Name = 'delete_everything'; Arguments = '{}' }
        @{ Code = 'InvalidArguments'; Name = 'get_inventory'; Arguments = 'nicht json' }
        @{ Code = 'InvalidId'; Name = 'get_program_details'; Arguments = '{"id":"C:\\Windows"}' }
        @{ Code = 'UnknownId'; Name = 'get_program_details'; Arguments = '{"id":"p-000000000000"}' }
        @{ Code = 'InvalidLimit'; Name = 'get_inventory'; Arguments = '{"limit":5000}' }
        @{ Code = 'InvalidRating'; Name = 'get_inventory'; Arguments = '{"rating":"Lila"}' }
    ) {
        $r = Invoke-Tool $Name $Arguments
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be $Code
        $data = Get-Content2 $r
        $data.error_code | Should -Be $Code
        $data.error | Should -Not -BeNullOrEmpty
        $data.error | Should -Not -Be "AdvisorError$Code"   # Text vorhanden, nicht nur der Schlüssel
    }

    It 'erzeugt Vorschläge, führt aber nichts aus' {
        Mock -ModuleName SoftwareInventory Update-Software { throw 'darf nicht laufen' }
        Mock -ModuleName SoftwareInventory Uninstall-Software { throw 'darf nicht laufen' }

        $r = Invoke-Tool propose_update "{`"id`":`"$oldId`",`"reason`":`"Aktiv ausgenutzte Lücke, liegt in C:\\Users\\normb`"}"
        $r.Ok | Should -BeTrue
        $r.Proposal.Action | Should -Be 'Update'
        $r.Proposal.Name | Should -Be 'Old Tool'
        $r.Proposal.Reason | Should -Not -Match 'normb'
        $r.Proposal.Rating.Name | Should -Be 'Old Tool'
        $r.Code | Should -Be 'ProposalCreated'
        (Get-Content2 $r).status_code | Should -Be 'ProposalCreated'
        $r.Content | Should -Not -Match 'Rating'

        (Invoke-Tool propose_uninstall "{`"id`":`"$zipId`",`"reason`":`"wird nicht mehr gebraucht`"}").Proposal.Action | Should -Be 'Uninstall'
        Should -Invoke -ModuleName SoftwareInventory Update-Software -Times 0
        Should -Invoke -ModuleName SoftwareInventory Uninstall-Software -Times 0
    }

    It 'lehnt Update-Vorschläge ohne bekanntes Update und ohne Begründung ab' {
        (Invoke-Tool propose_update "{`"id`":`"$zipId`",`"reason`":`"x`"}").Code | Should -Be 'NoUpdateKnown'
        (Invoke-Tool propose_uninstall "{`"id`":`"$zipId`",`"reason`":`"  `"}").Code | Should -Be 'ReasonMissing'
    }

    It 'prüft Version und Lücken auf Wunsch neu und bereinigt das Ergebnis' {
        Mock -ModuleName SoftwareInventory Test-SoftwareUpdate { [pscustomobject] @{ Status = 'UpToDate'; InstalledVersion = '26.05'; LatestVersion = '26.05'; Source = 'Winget'; Confirmed = $true; Reason = $null } }
        Mock -ModuleName SoftwareInventory Get-SoftwareVulnerability {
            [pscustomobject] @{ Status = 'Unknown'; Reason = 'Dienst NVD nicht aktiviert'; Notes = @('Pfad C:\Users\normb'); Vulnerabilities = @(); Refuted = @([pscustomobject] @{ Note = 'KEV-Treffer CVE-2025-0411 widerlegt' }) }
        }
        (Get-Content2 (Invoke-Tool check_latest_version "{`"id`":`"$zipId`"}")).status | Should -Be 'UpToDate'
        $v = Invoke-Tool search_vulnerabilities "{`"id`":`"$zipId`"}"
        $v.Content | Should -Not -Match 'normb'
        (Get-Content2 $v).refuted | Should -Be @('KEV-Treffer CVE-2025-0411 widerlegt')
    }

    It 'gibt keine Nutzungsspuren (Zeitstempel, Startzähler, Spurenart) und keine Pfade an die KI, auch nicht für Treffer auf nicht erreichbaren Laufwerken' {
        $usb = New-TestRating 'tool' Gray @{
            FilePath = 'F:\Users\normb\PortableApps\tool.exe'; InstallLocation = 'F:\Users\normb\PortableApps'
            Evidence = [string[]] @('UserAssist', 'Process'); LastRun = '2026-10-01T10:00:00.0000000Z'; RunCount = 4711
            Flags = [string[]] @('PathUnreachable')
        } -VulnStatus Unknown -Reasons @('Pfad nicht erreichbar: Das Laufwerk ist gerade nicht verbunden (z. B. abgezogener USB-Stick). Gefunden über Nutzungsspuren.')
        Set-AdvisorContext -Rating @($usb)
        $id = InModuleScope SoftwareInventory -Parameters @{ R = $usb.Record } { Get-AdvisorProgramId $R }

        $all = (Invoke-Tool get_inventory).Content + (Invoke-Tool get_program_details "{`"id`":`"$id`"}").Content
        foreach ($forbidden in 'LastRun', 'last_run', 'RunCount', 'run_count', '4711', '2026-10-01', 'Evidence', 'UserAssist', 'PortableApps', 'normb') {
            $all | Should -Not -Match ([regex]::Escape($forbidden)) -Because "'$forbidden' darf nicht an die KI gehen"
        }
        $all | Should -Match 'Pfad nicht erreichbar'
    }

    It 'liest ohne übergebene Daten einmal selbst ein' {
        Set-AdvisorContext -Clear
        Mock -ModuleName SoftwareInventory Get-SoftwareInventory { $script:ratings[2].Record }
        Mock -ModuleName SoftwareInventory Get-SecurityRating { $script:ratings[2] }
        (Get-Content2 (Invoke-Tool get_inventory)).programs.name | Should -Be @('Firefox')
        (Get-Content2 (Invoke-Tool get_inventory)).programs.name | Should -Be @('Firefox')
        Should -Invoke -ModuleName SoftwareInventory Get-SoftwareInventory -Times 1 -Exactly
    }
}
