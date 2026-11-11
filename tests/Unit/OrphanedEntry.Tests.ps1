BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force

    function New-UninstallKey {
        param([string] $Root, [string] $Name, [hashtable] $Values)
        $key = New-Item -Path $Root -Name $Name -Force
        foreach ($v in $Values.GetEnumerator()) {
            $type = if ($v.Value -is [int]) { 'DWord' } else { 'String' }
            New-ItemProperty -Path $key.PSPath -Name $v.Key -Value $v.Value -PropertyType $type | Out-Null
        }
    }

    function New-OrphanRecord {
        param([string] $Name = 'Jan 0.5.16', [string] $Version = '0.5.16', [string] $Publisher = 'Jan', [switch] $Orphaned)
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; V = $Version; P = $Publisher; O = [bool] $Orphaned } {
            $r = New-SoftwareRecord -Name $N -Source Registry -Property @{ Version = $V; Publisher = $P; Scope = 'User' }
            if ($O) { $r.Flags = [string[]] @('Orphaned') }
            $r
        }
    }
}

Describe 'Verwaiste Uninstall-Einträge erkennen' {
    BeforeAll {
        # Nachbildung des Jan-Falls (11.11.): alter Electron-Rest neben der echten Installation im selben Ordner,
        # einmal „jan“, einmal „Jan“ geschrieben (Windows unterscheidet das nicht).
        $programs = Join-Path $TestDrive 'Programs'
        New-Item -ItemType Directory -Path (Join-Path $programs 'Jan') -Force | Out-Null
        'x' | Set-Content (Join-Path $programs 'Jan\Jan-Desktop.exe')
        'x' | Set-Content (Join-Path $programs 'Jan\uninstall.exe')
        $existing = Join-Path $programs 'Jan\Jan-Desktop.exe'
        # Ein Laufwerksbuchstabe, den es gerade nicht gibt
        $freeDrive = @('Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z') | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1

        $user = 'TestRegistry:\User'
        New-Item -Path $user -Force | Out-Null
        New-UninstallKey $user '26e92a45-3e3b-5b43-bb59-04bf3b027b64' @{
            DisplayName = 'Jan 0.5.16'; DisplayVersion = '0.5.16'; Publisher = 'Jan'
            DisplayIcon = "$programs\jan\uninstallerIcon.ico"
            UninstallString = "`"$programs\jan\Uninstall Jan.exe`" /currentuser"
            QuietUninstallString = "`"$programs\jan\Uninstall Jan.exe`" /currentuser /S"
        }
        New-UninstallKey $user 'Jan' @{
            DisplayName = 'Jan'; DisplayVersion = '0.8.8'; Publisher = 'Menlo Research Pte. Ltd.'
            InstallLocation = "`"$programs\Jan`""; DisplayIcon = "`"$programs\Jan\Jan-Desktop.exe`""
            UninstallString = "`"$programs\Jan\uninstall.exe`""
        }
        New-UninstallKey $user 'Msi' @{ DisplayName = 'Msi App'; DisplayVersion = '1.0'; WindowsInstaller = 1; UninstallString = "`"$programs\gone\setup.exe`" /x" }
        New-UninstallKey $user 'Rundll' @{ DisplayName = 'Rundll App'; DisplayVersion = '1.0'; UninstallString = "rundll32.exe $programs\gone\app.dll,Uninstall" }
        New-UninstallKey $user 'Unreachable' @{ DisplayName = 'Stick App'; DisplayVersion = '1.0'; UninstallString = "`"$($freeDrive):\Apps\uninst.exe`"" }
        New-UninstallKey $user 'Unc' @{ DisplayName = 'Share App'; DisplayVersion = '1.0'; UninstallString = '"\\server\share\uninst.exe"' }
        New-UninstallKey $user 'Location' @{ DisplayName = 'Location App'; DisplayVersion = '1.0'; UninstallString = "`"$programs\gone\uninst.exe`""; InstallLocation = "$programs\Jan" }
        New-UninstallKey $user 'Icon' @{ DisplayName = 'Icon App'; DisplayVersion = '1.0'; UninstallString = "`"$programs\gone\uninst.exe`""; DisplayIcon = "$existing,0" }
        New-UninstallKey $user 'Quiet' @{ DisplayName = 'Quiet App'; DisplayVersion = '1.0'; UninstallString = "`"$programs\gone\uninst.exe`""; QuietUninstallString = "`"$existing`" /S" }
        New-UninstallKey $user 'NoCommand' @{ DisplayName = 'No Command'; DisplayVersion = '1.0' }

        $result = InModuleScope SoftwareInventory -Parameters @{ U = $user } {
            Get-RegistrySoftware -Location @(@{ Path = $U; Scope = 'User'; Architecture = $null })
        }
        function Get-Flag([string] $Name) { @(($result | Where-Object Name -EQ $Name).Flags) }
    }

    It 'erkennt den alten Jan-Eintrag als verwaist, die echte Installation nicht' {
        Get-Flag 'Jan 0.5.16' | Should -Be @('Orphaned')
        Get-Flag 'Jan' | Should -Not -Contain 'Orphaned'
    }

    It 'wertet <Name> nie als verwaist' -TestCases @(
        @{ Name = 'Msi App' }
        @{ Name = 'Rundll App' }
        @{ Name = 'Stick App' }
        @{ Name = 'Share App' }
        @{ Name = 'Location App' }
        @{ Name = 'Icon App' }
        @{ Name = 'Quiet App' }
        @{ Name = 'No Command' }
    ) {
        Get-Flag $Name | Should -Not -Contain 'Orphaned'
    }
}

Describe 'Verwaiste Einträge in Prüfung, Ampel und Aktionen' {
    BeforeEach {
        Mock -ModuleName SoftwareInventory Write-DataNote { }
        Mock -ModuleName SoftwareInventory Read-InventorySetting {
            $s = InModuleScope SoftwareInventory { New-DefaultSetting }
            foreach ($n in 'Winget', 'GitHub', 'NVD', 'CIRCL', 'KEV') { if ($s.Services.PSObject.Properties[$n]) { $s.Services.$n = $true } }
            $s
        }
    }

    It 'fragt für verwaiste Einträge keine Version ab' {
        Mock -ModuleName SoftwareInventory Get-WingetLatestVersion { throw 'darf nicht aufgerufen werden' }
        Mock -ModuleName SoftwareInventory Get-GitHubLatestVersion { throw 'darf nicht aufgerufen werden' }
        Mock -ModuleName SoftwareInventory Get-WingetSearchLatestVersion { throw 'darf nicht aufgerufen werden' }
        $u = New-OrphanRecord -Orphaned | Test-SoftwareUpdate
        $u.Status | Should -Be 'Unknown'
        $u.Reason.Code | Should -Be 'OrphanedEntry'
        $u.LatestVersion | Should -BeNullOrEmpty
    }

    It 'sucht für verwaiste Einträge keine Lücken, auch nicht über KEV' {
        Mock -ModuleName SoftwareInventory Get-NvdCve { throw 'darf nicht aufgerufen werden' }
        Mock -ModuleName SoftwareInventory Get-CirclCve { throw 'darf nicht aufgerufen werden' }
        Mock -ModuleName SoftwareInventory Get-KevIndex { @{} }
        $v = New-OrphanRecord -Orphaned | Get-SoftwareVulnerability
        $v.Status | Should -Be 'Unknown'
        $v.Reason.Code | Should -Be 'OrphanedEntry'
        $v.Vulnerabilities | Should -BeNullOrEmpty
    }

    It 'ist grau mit eigenem Grund und nennt die neuere Installation daneben' {
        Mock -ModuleName SoftwareInventory Test-SoftwareUpdate {
            foreach ($r in $InputObject) { [pscustomobject] @{ Status = 'UpToDate'; InstalledVersion = $r.Version; LatestVersion = $r.Version; Source = 'Winget'; Confirmed = $true; Reason = $null; Record = $r } }
        }
        Mock -ModuleName SoftwareInventory Get-SoftwareVulnerability {
            foreach ($r in $InputObject) { [pscustomobject] @{ Status = 'Checked'; Reason = $null; Notes = @(); Vulnerabilities = @(); Refuted = @(); Record = $r } }
        }
        $ratings = @(
            New-OrphanRecord -Orphaned
            New-OrphanRecord -Name 'Jan' -Version '0.8.8' -Publisher 'Menlo Research Pte. Ltd.'
            New-OrphanRecord -Name 'Other Tool' -Version '9.0' -Publisher 'Contoso'
        ) | Get-SecurityRating
        $orphan = $ratings | Where-Object Name -EQ 'Jan 0.5.16'
        $orphan.Rating | Should -Be 'Gray'
        $orphan.Reasons.Code | Should -Be @('OrphanedEntry', 'NewerInstallNextTo')
        $orphan.Reasons[0].Text | Should -Be 'Programm nicht mehr vorhanden, nur Restanzeige in Windows'
        $orphan.Reasons[1].Text | Should -Be 'Neuere Installation daneben: Jan 0.8.8'
        ($ratings | Where-Object Name -EQ 'Jan').Rating | Should -Be 'Green'
    }

    It 'nennt keine neuere Installation, wenn es nur ältere oder fremde gibt' {
        $own = New-OrphanRecord -Orphaned
        $older = New-OrphanRecord -Name 'Jan' -Version '0.4.0' -Publisher 'Menlo Research Pte. Ltd.'
        $other = New-OrphanRecord -Name 'Janus' -Version '9.0' -Publisher 'Meetecho'
        InModuleScope SoftwareInventory -Parameters @{ R = $own; C = @($own, $older, $other) } { Find-NewerInstallation -Record $R -Candidate $C -Catalog (Get-SoftwareCatalog) } |
            Should -BeNullOrEmpty
    }

    It 'plant für verwaiste Einträge weder Update noch Deinstallation (<Action>)' -TestCases @(@{ Action = 'Update' }, @{ Action = 'Uninstall' }) {
        $plan = InModuleScope SoftwareInventory -Parameters @{ R = (New-OrphanRecord -Orphaned); A = $Action } { New-ActionPlan -Action $A -Record $R }
        $plan.Result | Should -Be 'Unsupported'
        $plan.Message.Code | Should -Be 'OrphanedEntry'
    }

    It 'lehnt Vorschläge des Beraters für verwaiste Einträge ab (<Tool>)' -TestCases @(@{ Tool = 'propose_update' }, @{ Tool = 'propose_uninstall' }) {
        $record = New-OrphanRecord -Orphaned
        $rating = [pscustomobject] @{
            Name = $record.Name; Version = $record.Version; Rating = 'Gray'; Reasons = @(); LatestVersion = $null
            UpdateStatus = [pscustomobject] @{ Status = 'Outdated'; InstalledVersion = '0.5.16'; LatestVersion = '0.8.8'; Source = 'GitHub'; Confirmed = $true; Reason = $null }
            VulnerabilityStatus = [pscustomobject] @{ Status = 'Unknown'; Reason = $null; Notes = @(); Vulnerabilities = @(); Refuted = @() }
            Record = $record
        }
        Set-AdvisorContext -Rating @($rating)
        try {
            $id = InModuleScope SoftwareInventory -Parameters @{ R = $record } { Get-AdvisorProgramId $R }
            $r = Invoke-AdvisorTool -Name $Tool -ArgumentsJson "{`"id`":`"$id`",`"reason`":`"alt`"}"
            $r.Ok | Should -BeFalse
            $r.Code | Should -Be 'OrphanedEntry'
        }
        finally { Set-AdvisorContext -Clear }
    }
}
