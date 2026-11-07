BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-Msg {
        param([string] $Code, [object[]] $Arguments = @())
        InModuleScope SoftwareInventory -Parameters @{ C = $Code; A = $Arguments } { New-InventoryMessage $C $A }
    }

    function New-LevelRating {
        param([string] $Name, [string] $Source = 'Registry', [hashtable] $Property, [string] $Rating = 'Green', [object[]] $Vulns = @())
        $record = InModuleScope SoftwareInventory -Parameters @{ N = $Name; S = $Source; P = $Property } { New-SoftwareRecord -Name $N -Source $S -Property $P }
        [pscustomobject] @{
            Name                = $Name
            Version             = $Property.Version
            Rating              = $Rating
            Reasons             = @(New-Msg NoFindings)
            LatestVersion       = $Property.Version
            UpdateStatus        = [pscustomobject] @{ Status = 'UpToDate'; InstalledVersion = $Property.Version; LatestVersion = $Property.Version; Source = 'Winget'; Confirmed = $true; Reason = $null }
            VulnerabilityStatus = [pscustomobject] @{ Status = 'Checked'; Reason = $null; Notes = @(); Vulnerabilities = @($Vulns); Refuted = @() }
            Record              = $record
        }
    }

    function Get-AllContent {
        # Alles, was das Modell auf der Stufe bekäme: Liste und Details jedes sichtbaren Programms.
        param([int] $Level)
        InModuleScope SoftwareInventory -Parameters @{ L = $Level } {
            $args0 = if ($L -eq 0) { '{}' } else { '{"limit":200}' }
            $inventory = Invoke-AdvisorToolAtLevel -Name get_inventory -ArgumentsJson $args0 -Level $L
            $texts = @($inventory.Content)
            $data = $inventory.Content | ConvertFrom-Json -AsHashtable
            $details = @{}
            foreach ($p in @($data['programs']) | Where-Object { $_ }) {
                $d = Invoke-AdvisorToolAtLevel -Name get_program_details -ArgumentsJson (@{ id = $p['id'] } | ConvertTo-Json -Compress) -Level $L
                $texts += $d.Content
                $details[$p['name']] = $d.Content | ConvertFrom-Json -AsHashtable
            }
            [pscustomobject] @{ Inventory = $data; Details = $details; Text = $texts -join "`n" }
        }
    }

    # Felder, die auf keiner Stufe an die KI gehen dürfen
    $script:NeverSent = @(
        '{11111111-2222-3333-4444-555555555555}', 'MsiExec', 'HKLM:', 'RegistryKey', 'ProductCode', 'UninstallString',
        'DisplayIcon', 'Contoso.Old_1.0_x64__abc', 'AABBCCDDEEFF00112233', 'E:\\Copies', 'CopyPaths', '2024-03-01', 'InstallDate',
        'LastRun', 'last_run', 'RunCount', 'run_count', '4711', 'UserAssist', 'Evidence', 'FileScan', 'scan-tool.exe', 'trace-tool.exe', 'normb'
    )
}

Describe 'KI-Berater: Freigabestufen' {
    BeforeAll {
        Mock -ModuleName SoftwareInventory Get-PrivateIdentity {
            [pscustomobject] @{ UserProfile = 'C:\Users\normb'; UserName = 'normb'; ComputerName = 'NORM-PC'; Domain = 'NORM-PC' }
        }
        $recent = [datetime]::UtcNow.AddDays(-10).ToString('o')
        $old = [datetime]::UtcNow.AddDays(-400).ToString('o')
        $script:Ratings = @(
            New-LevelRating 'Old Tool' -Rating Red -Property @{
                Version = '1.0'; Publisher = 'Contoso'; InstallType = 'MSI'; Scope = 'Machine'; Architecture = 'X64'
                WingetId = 'Contoso.Old'; WingetSource = 'winget'; InstallLocation = (Join-Path $env:ProgramFiles 'Old')
                RegistryKey = 'HKLM:\SOFTWARE\X\Old'; ProductCode = '{11111111-2222-3333-4444-555555555555}'
                UninstallString = 'MsiExec.exe /X{11111111-2222-3333-4444-555555555555}'; DisplayIcon = 'C:\Program Files\Old\old.ico'
                PackageFullName = 'Contoso.Old_1.0_x64__abc'; InstallDate = '2024-03-01'
            } -Vulns @([pscustomobject] @{ CveId = 'CVE-2026-0001'; Assessment = 'Affected'; Kev = $true; Score = 9.8; Epss = 0.5; Note = $null; Description = 'Lücke' })
            New-LevelRating 'Scan Tool' -Source Portable -Property @{
                Version = '2.0'; Publisher = 'Fabrikam'; InstallType = 'Portable'
                FilePath = 'C:\Users\normb\Downloads\scan-tool.exe'; InstallLocation = 'C:\Users\normb\Downloads'
                CopyPaths = [string[]] @('E:\Copies\scan-tool.exe'); Sha256 = 'AABBCCDDEEFF00112233'
                SignatureStatus = 'NotSigned'; Evidence = [string[]] @('FileScan'); Flags = [string[]] @('Unsigned', 'InDownloadsOrTemp', 'Autostart')
                LastRun = $old; RunCount = 4711
            }
            New-LevelRating 'Trace Tool' -Source Portable -Property @{
                Version = '3.0'; Publisher = 'Northwind'; InstallType = 'Portable'
                FilePath = 'D:\Apps\trace-tool.exe'; Evidence = [string[]] @('UserAssist', 'Autostart'); LastRun = $recent; RunCount = 4711
            }
        )
        Set-AdvisorContext -Rating $script:Ratings
        # Fundort-Klassen ohne echte Laufwerke
        Mock -ModuleName SoftwareInventory Get-AdvisorDriveType { 'Fixed' }
        # Profilordner der Testdaten (Get-AdvisorLocationKind liest USERPROFILE)
        $script:SavedProfile = $env:USERPROFILE
        $env:USERPROFILE = 'C:\Users\normb'
    }
    AfterAll {
        $env:USERPROFILE = $script:SavedProfile
        Set-AdvisorContext -Clear
    }

    It 'gibt <Item> auf keiner Stufe an die KI' -ForEach @(0..4 | ForEach-Object { @{ Level = $_; Item = "Stufe $_" } }) {
        $text = (Get-AllContent -Level $Level).Text
        foreach ($forbidden in $script:NeverSent) {
            $text | Should -Not -Match ([regex]::Escape($forbidden)) -Because "'$forbidden' darf auf Stufe $Level nicht an die KI gehen"
        }
    }

    It 'zeigt auf Stufe 0 nur Anzahlen, Ampelverteilung und CVE-Nummern' {
        $c = Get-AllContent -Level 0
        $c.Inventory.Keys | Sort-Object | Should -Be @('cve_ids', 'cve_ids_truncated', 'kev', 'programs_in_scan', 'ratings', 'share_level', 'updates_available', 'vulnerabilities')
        $c.Inventory.programs_in_scan | Should -Be 1   # portable Programme zählen erst ab Stufe 3
        $c.Inventory.ratings.Red | Should -Be 1
        $c.Inventory.cve_ids | Should -Be @('CVE-2026-0001')
        $c.Text | Should -Not -Match 'Old Tool|Contoso|p-[0-9a-f]{12}'
    }

    It 'lehnt auf Stufe 0 <Case> ab' -ForEach @(
        @{ Case = 'Parameter für get_inventory'; Tool = 'get_inventory'; Arguments = '{"filter":"Old"}' }
        @{ Case = 'get_program_details'; Tool = 'get_program_details'; Arguments = '{"id":"p-000000000000"}' }
        @{ Case = 'propose_update'; Tool = 'propose_update'; Arguments = '{"id":"p-000000000000","reason":"x"}' }
    ) {
        $r = InModuleScope SoftwareInventory -Parameters @{ T = $Tool; A = $Arguments } { Invoke-AdvisorToolAtLevel -Name $T -ArgumentsJson $A -Level 0 }
        $r.Ok | Should -BeFalse
        $r.Code | Should -Be 'ShareLevelTooLow'
    }

    It 'zeigt auf Stufe 1 die Programmliste ohne Installationsdetails und ohne portable Programme' {
        $c = Get-AllContent -Level 1
        $c.Inventory.programs.name | Should -Be @('Old Tool')
        $d = $c.Details['Old Tool']
        foreach ($key in 'id', 'name', 'publisher', 'version', 'rating', 'reasons', 'vulnerability_list', 'refuted', 'otherPlatform') { $d.Keys | Should -Contain $key }
        foreach ($key in 'sources', 'install_type', 'scope', 'architecture', 'winget_id', 'winget_source', 'install_location', 'signature_status', 'location_kind', 'last_used', 'autostart') {
            $d.Keys | Should -Not -Contain $key -Because "$key gehört nicht zu Stufe 1"
        }
        $c.Text | Should -Not -Match 'Program Files|PROGRAMFILES|Scan Tool|Trace Tool'
    }

    It 'zeigt auf Stufe 2 zusätzlich Installationsdetails mit bereinigtem Pfad' {
        $c = Get-AllContent -Level 2
        $c.Inventory.programs.name | Should -Be @('Old Tool')
        $d = $c.Details['Old Tool']
        $d.install_type | Should -Be 'MSI'
        $d.scope | Should -Be 'Machine'
        $d.architecture | Should -Be 'X64'
        $d.winget_id | Should -Be 'Contoso.Old'
        $d.install_location | Should -Be '%PROGRAMFILES%\Old'
        foreach ($key in 'signature_status', 'location_kind', 'last_used', 'autostart') { $d.Keys | Should -Not -Contain $key }
    }

    It 'zeigt auf Stufe 3 portable Programme der Dateisuche mit Fundort-Art statt Pfad, ohne Nutzungsspuren' {
        $c = Get-AllContent -Level 3
        $c.Inventory.programs.name | Sort-Object | Should -Be @('Old Tool', 'Scan Tool')
        $d = $c.Details['Scan Tool']
        $d.kind | Should -Be 'portable'
        $d.signature_status | Should -Be 'NotSigned'
        $d.location_kind | Should -Be 'Downloads'
        $d.flags | Should -Be @('unsigned', 'in_downloads_or_temp')
        foreach ($key in 'install_location', 'last_used', 'autostart') { $d.Keys | Should -Not -Contain $key -Because "$key gehört nicht zu Stufe 3" }
        $c.Text | Should -Not -Match 'Downloads\\\\|Trace Tool'
    }

    It 'zeigt auf Stufe 4 auch Funde über Nutzungsspuren, nur mit groben Klassen' {
        $c = Get-AllContent -Level 4
        $c.Inventory.programs.name | Sort-Object | Should -Be @('Old Tool', 'Scan Tool', 'Trace Tool')
        $c.Details['Trace Tool'].last_used | Should -Be 'within_1_month'
        $c.Details['Trace Tool'].autostart | Should -BeTrue
        $c.Details['Trace Tool'].location_kind | Should -Be 'OtherDrive'
        $c.Details['Scan Tool'].last_used | Should -Be 'older'
        $c.Details['Scan Tool'].autostart | Should -BeTrue   # Merkmal Autostart, erst ab Stufe 4
        $c.Details['Old Tool'].Keys | Should -Not -Contain 'last_used'   # installierte Programme haben keine Spurfelder
    }

    It 'beschreibt auf Stufe 0 nur get_inventory ohne Parameter' {
        Mock -ModuleName SoftwareInventory Get-AdvisorShareLevel { 0 }
        $tools = @(Get-AdvisorTool)
        $tools.Name | Should -Be @('get_inventory')
        ($tools[0].ParametersJson | ConvertFrom-Json -AsHashtable).properties.Count | Should -Be 0
    }

    It 'zeigt in der Vorschau genau die Antworten der Tools auf Stufe <Level>' -ForEach @(@{ Level = 0 }, @{ Level = 1 }, @{ Level = 3 }) {
        $p = Get-AdvisorDataPreview -Level $Level
        $p.Level | Should -Be $Level
        $expected = InModuleScope SoftwareInventory -Parameters @{ L = $Level } {
            Invoke-AdvisorToolAtLevel -Name get_inventory -ArgumentsJson $(if ($L -eq 0) { '{}' } else { '{"limit":5}' }) -Level $L
        }
        $p.Inventory | Should -Be $expected.Content
        if ($Level -eq 0) { $p.Details | Should -BeNullOrEmpty } else { ($p.Details | ConvertFrom-Json).name | Should -Be 'Old Tool' }
        $p.Inventory + $p.Details | Should -Not -Match 'normb'
    }
}

Describe 'Freigabestufe aus den Einstellungen' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
    }

    It 'beginnt ohne Einstellungsdatei mit lokal 3 und extern 1, ohne Hinweis' {
        $s = Get-InventorySetting
        $s.Advisor.ShareLevel.Local | Should -Be 3
        $s.Advisor.ShareLevel.External | Should -Be 1
        $s.Advisor.ShareLevelNoticePending | Should -BeFalse
    }

    It 'setzt ältere Einstellungen ohne Freigabestufe auf lokal 2 und merkt den Hinweis' {
        '{"Advisor":{"Enabled":true,"Preset":"Ollama","Endpoint":"http://localhost:11434/v1","Model":"qwen"}}' | Set-Content -LiteralPath $settingsFile
        $s = Get-InventorySetting
        $s.Advisor.ShareLevel.Local | Should -Be 2
        $s.Advisor.ShareLevel.External | Should -Be 1
        $s.Advisor.ShareLevelNoticePending | Should -BeTrue
        InModuleScope SoftwareInventory { Get-AdvisorShareLevel -ProviderKind Local } | Should -Be 2
    }

    It 'behält die Stufe 2 nach dem Speichern, bis der Benutzer sie ändert' {
        '{"Advisor":{"Enabled":false}}' | Set-Content -LiteralPath $settingsFile
        Set-InventorySetting -AdvisorShareLevelNoticePending $false | Out-Null
        $s = Get-InventorySetting
        $s.Advisor.ShareLevel.Local | Should -Be 2
        $s.Advisor.ShareLevelNoticePending | Should -BeFalse
        $s = Set-InventorySetting -AdvisorShareLevelLocal 4
        $s.Advisor.ShareLevel.Local | Should -Be 4
        (Get-InventorySetting).Advisor.ShareLevel.Local | Should -Be 4
    }

    It 'löscht den Hinweis, wenn der Benutzer eine Stufe wählt' {
        '{"Advisor":{"Enabled":true}}' | Set-Content -LiteralPath $settingsFile
        (Set-InventorySetting -AdvisorShareLevelLocal 3).Advisor.ShareLevelNoticePending | Should -BeFalse
    }

    It 'verwirft ungültige Stufen aus der Datei' {
        '{"Advisor":{"ShareLevel":{"Local":9,"External":4}}}' | Set-Content -LiteralPath $settingsFile
        $s = Get-InventorySetting
        $s.Advisor.ShareLevel.Local | Should -Be 3
        $s.Advisor.ShareLevel.External | Should -Be 1
    }

    It 'erlaubt extern höchstens Stufe 3' {
        { Set-InventorySetting -AdvisorShareLevelExternal 4 } | Should -Throw
        (Set-InventorySetting -AdvisorShareLevelExternal 3).Advisor.ShareLevel.External | Should -Be 3
    }

    It 'begrenzt die wirksame Stufe auf die Grenze der Anbieterart' {
        InModuleScope SoftwareInventory {
            $s = New-DefaultSetting
            $s.Advisor.ShareLevel.External = 4   # z. B. von Hand in die Datei geschrieben
            Get-AdvisorShareLevel -ProviderKind External -Setting $s | Should -Be 3
            Get-AdvisorShareLimit -ProviderKind Local | Should -Be 4
        }
    }
}

Describe 'Fundort-Art und Nutzungsklassen' {
    BeforeAll {
        $script:SavedProfile = $env:USERPROFILE
        $env:USERPROFILE = 'C:\Users\normb'
    }
    AfterAll { $env:USERPROFILE = $script:SavedProfile }

    It '<Path> ergibt <Expected>' -ForEach @(
        @{ Path = 'C:\Users\normb\Downloads\a.exe'; Drive = 'Fixed'; Expected = 'Downloads' }
        @{ Path = 'C:\Users\normb\Tools\a.exe'; Drive = 'Fixed'; Expected = 'UserProfile' }
        @{ Path = 'C:\Tools\a.exe'; Drive = 'Fixed'; Expected = 'Other' }
        @{ Path = 'F:\a.exe'; Drive = 'Removable'; Expected = 'RemovableDrive' }
        @{ Path = 'N:\a.exe'; Drive = 'Network'; Expected = 'NetworkDrive' }
        @{ Path = '\\server\share\a.exe'; Drive = 'Fixed'; Expected = 'NetworkDrive' }
        @{ Path = 'D:\Apps\a.exe'; Drive = 'Fixed'; Expected = 'OtherDrive' }
    ) {
        $script:Drive = $Drive
        Mock -ModuleName SoftwareInventory Get-AdvisorDriveType { $script:Drive }
        InModuleScope SoftwareInventory -Parameters @{ P = $Path } { Get-AdvisorLocationKind $P } | Should -Be $Expected
    }

    It 'erkennt Temp und Programme' {
        InModuleScope SoftwareInventory { Get-AdvisorLocationKind (Join-Path $env:TEMP 'x\a.exe') } | Should -Be 'Temp'
        InModuleScope SoftwareInventory { Get-AdvisorLocationKind (Join-Path $env:ProgramFiles 'X\a.exe') } | Should -Be 'ProgramFiles'
    }

    It 'ordnet <Days> Tage als <Expected> ein' -ForEach @(
        @{ Days = 1; Expected = 'within_1_month' }
        @{ Days = 31; Expected = 'within_1_month' }
        @{ Days = 32; Expected = '1_to_6_months' }
        @{ Days = 183; Expected = '1_to_6_months' }
        @{ Days = 184; Expected = 'older' }
    ) {
        $now = [datetime]::new(2026, 11, 7, 12, 0, 0, [DateTimeKind]::Utc)
        InModuleScope SoftwareInventory -Parameters @{ L = $now.AddDays(-$Days).ToString('o'); N = $now } { Get-AdvisorLastUsedClass -LastRun $L -Now $N } | Should -Be $Expected
    }

    It 'nennt fehlende Spuren unknown, nicht „nie“' {
        InModuleScope SoftwareInventory { Get-AdvisorLastUsedClass -LastRun $null } | Should -Be 'unknown'
        InModuleScope SoftwareInventory { Get-AdvisorLastUsedClass -LastRun 'kein Datum' } | Should -Be 'unknown'
    }
}

Describe 'Adresse des KI-Servers: nur lokal' {
    BeforeEach {
        # Namensauflösung ohne Netz: IP-Literale wie echt, Namen aus der Tabelle
        $script:Dns = @{
            'localhost' = @('127.0.0.1', '::1')
            'nas.lan'   = @('192.168.1.20')
            'mixed.lan' = @('192.168.1.21', '8.8.8.8')
            'cloud.example' = @('203.0.113.10')
        }
        Mock -ModuleName SoftwareInventory Resolve-AdvisorHost {
            $ip = $null
            if ([System.Net.IPAddress]::TryParse($HostName, [ref] $ip)) { return $ip }
            foreach ($a in @($script:Dns[$HostName])) { if ($a) { [System.Net.IPAddress]::Parse($a) } }
        }
    }

    It '<Endpoint> ist <Network> (Ok <Ok>)' -ForEach @(
        @{ Endpoint = 'http://localhost:11434/v1'; Network = 'Loopback'; Ok = $true; Code = $null }
        @{ Endpoint = 'http://127.0.0.1:1234/v1'; Network = 'Loopback'; Ok = $true; Code = $null }
        @{ Endpoint = 'http://[::1]:11434/v1'; Network = 'Loopback'; Ok = $true; Code = $null }
        @{ Endpoint = 'https://nas.lan/v1'; Network = 'Private'; Ok = $true; Code = $null }
        @{ Endpoint = 'http://nas.lan:11434/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://10.1.2.3/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://172.31.255.254/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://169.254.10.1/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://[fe80::1]:11434/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://[fd12:3456::5]/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://[::ffff:192.168.1.5]/v1'; Network = 'Private'; Ok = $true; Code = 'AdvisorEndpointUnencrypted' }
        @{ Endpoint = 'http://172.32.0.1/v1'; Network = 'Public'; Ok = $false; Code = 'AdvisorEndpointNotLocal' }
        @{ Endpoint = 'http://100.64.1.1/v1'; Network = 'Public'; Ok = $false; Code = 'AdvisorEndpointNotLocal' }
        @{ Endpoint = 'https://8.8.8.8/v1'; Network = 'Public'; Ok = $false; Code = 'AdvisorEndpointNotLocal' }
        @{ Endpoint = 'https://cloud.example/v1'; Network = 'Public'; Ok = $false; Code = 'AdvisorEndpointNotLocal' }
        @{ Endpoint = 'http://mixed.lan/v1'; Network = 'Public'; Ok = $false; Code = 'AdvisorEndpointNotLocal' }
        @{ Endpoint = 'http://nowhere.invalid/v1'; Network = 'Unresolvable'; Ok = $false; Code = 'AdvisorEndpointUnresolvable' }
        @{ Endpoint = 'ftp://nas.lan/v1'; Network = 'Invalid'; Ok = $false; Code = 'AdvisorEndpointInvalid' }
    ) {
        $c = Get-AdvisorEndpointCheck -Endpoint $Endpoint
        $c.Network | Should -Be $Network
        $c.Ok | Should -Be $Ok
        if ($Code) { $c.Message.Code | Should -Be $Code } else { $c.Message | Should -BeNullOrEmpty }
        $c.Unencrypted | Should -Be ($Code -eq 'AdvisorEndpointUnencrypted')
    }

    It '<Address> ist <Network> (gemeinsame Tabelle mit der App)' -ForEach @(
        (Get-Content -Raw "$PSScriptRoot/../Data/advisor-address-cases.json" | ConvertFrom-Json).cases | ForEach-Object { @{ Address = $_.address; Network = $_.network } }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ A = $Address } { Get-IpAddressNetwork -Address ([System.Net.IPAddress]::Parse($A)) } | Should -Be $Network
    }

    It 'prüft die aufgelöste Adresse, nicht den Namen' {
        $script:Dns['localhost.evil.example'] = @('203.0.113.99')
        (Get-AdvisorEndpointCheck -Endpoint 'http://localhost.evil.example/v1').Ok | Should -BeFalse
        $script:Dns['public-name.example'] = @('192.168.7.7')
        (Get-AdvisorEndpointCheck -Endpoint 'http://public-name.example/v1').Network | Should -Be 'Private'
    }

    Context 'beim Speichern' {
        BeforeEach {
            $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
            Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        }

        It 'lehnt <Endpoint> mit Code <Code> ab' -ForEach @(
            @{ Endpoint = 'https://cloud.example/v1'; Code = 'AdvisorEndpointNotLocal' }
            @{ Endpoint = 'http://nowhere.invalid/v1'; Code = 'AdvisorEndpointUnresolvable' }
        ) {
            $err = $null
            try { Set-InventorySetting -AdvisorEndpoint $Endpoint | Out-Null } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.Exception.Data['Code'] | Should -Be $Code
            (Get-InventorySetting).Advisor.Endpoint | Should -BeNullOrEmpty
        }

        It 'speichert eine Adresse im privaten Netz' {
            (Set-InventorySetting -AdvisorEndpoint 'http://nas.lan:11434/v1').Advisor.Endpoint | Should -Be 'http://nas.lan:11434/v1'
        }
    }
}

Describe 'Verbindungsdaten und Bereinigung für die App' {
    BeforeEach {
        $settingsFile = Join-Path $TestDrive "settings-$([guid]::NewGuid()).json"
        Mock -ModuleName SoftwareInventory Get-SettingsPath { $settingsFile }
        Mock -ModuleName SoftwareInventory Read-StoredSecret { $null }
        Mock -ModuleName SoftwareInventory Read-EnvironmentSecret { $null }
    }

    It 'nimmt ohne eigene Adresse die der Vorgabe und hat ohne Schlüssel keinen' {
        Set-InventorySetting -AdvisorPreset LMStudio -AdvisorModel 'qwen3:8b' -AdvisorEnabled $true | Out-Null
        $c = Get-AdvisorConnection
        $c.Endpoint | Should -Be 'http://localhost:1234/v1'
        $c.Model | Should -Be 'qwen3:8b'
        $c.Enabled | Should -BeTrue
        $c.ProviderKind | Should -Be 'Local'
        $c.ApiKey | Should -BeNullOrEmpty
        $c.HasApiKey | Should -BeFalse
    }

    It 'liefert den Schlüssel nur als SecureString' {
        Mock -ModuleName SoftwareInventory Read-StoredSecret { 'sk-unsloth-geheim' } -ParameterFilter { $Service -eq 'Advisor' }
        $c = Get-AdvisorConnection
        $c.ApiKey | Should -BeOfType [System.Security.SecureString]
        $c.HasApiKey | Should -BeTrue
        [System.Net.NetworkCredential]::new('', $c.ApiKey).Password | Should -Be 'sk-unsloth-geheim'
        ($c | Out-String) | Should -Not -Match 'geheim'
        ($c | ConvertTo-Json -Depth 3) | Should -Not -Match 'geheim'
    }

    It 'schaltet nur mit Adresse und Modell ein (<Case>)' -ForEach @(
        @{ Case = 'ohne Modell'; Params = @{ AdvisorPreset = 'Ollama'; AdvisorEnabled = $true } }
        @{ Case = 'ohne Adresse'; Params = @{ AdvisorPreset = 'Custom'; AdvisorModel = 'm'; AdvisorEnabled = $true } }
    ) {
        $err = $null
        try { Set-InventorySetting @Params | Out-Null } catch { $err = $_ }
        $err.Exception.Data['Code'] | Should -Be 'AdvisorIncomplete'
        (Get-InventorySetting).Advisor.Enabled | Should -BeFalse
    }

    It 'prüft die Vollständigkeit nur, wenn Beraterwerte geändert werden' {
        Set-InventorySetting -AdvisorPreset Ollama -AdvisorModel 'm' -AdvisorEnabled $true | Out-Null
        { Set-InventorySetting -AdvisorModel '' } | Should -Throw
        (Set-InventorySetting -LogRetentionDays 20).Maintenance.LogRetentionDays | Should -Be 20
        (Set-InventorySetting -AdvisorEnabled $false -AdvisorModel '').Advisor.Model | Should -BeNullOrEmpty
    }

    It 'bereinigt Fragen des Benutzers wie die Tool-Antworten' {
        $text = Protect-AdvisorText -Text "Ich bin $env:USERNAME auf $env:COMPUTERNAME, Datei in $env:USERPROFILE\Downloads"
        $text | Should -Not -Match ([regex]::Escape($env:USERPROFILE))
        $text | Should -BeLike '*%USERPROFILE%\Downloads'
        $text | Should -Match '%COMPUTERNAME%'
        Protect-AdvisorText -Text '' | Should -Be ''
    }
}
