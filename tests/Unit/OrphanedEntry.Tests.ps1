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

Describe 'Remove-OrphanedEntry (8b-1, nur HKCU)' {
    BeforeEach {
        $script:AppDir = Join-Path $TestDrive "app-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $script:AppDir }
        $script:Programs = Join-Path $TestDrive 'Prog'
        New-Item -ItemType Directory -Path $script:Programs -Force | Out-Null
        Remove-Item -LiteralPath (Join-Path $script:Programs 'Uninstall Jan.exe') -Force -ErrorAction SilentlyContinue
        $script:User = 'TestRegistry:\RemoveUser'
        $script:Machine = 'TestRegistry:\RemoveMachine'
        Remove-Item -LiteralPath $script:User, $script:Machine -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:User, $script:Machine -Force | Out-Null
        foreach ($root in $script:User, $script:Machine) {
            New-UninstallKey $root 'janold' @{
                DisplayName = 'Jan 0.5.16'; DisplayVersion = '0.5.16'; Publisher = 'Jan'
                DisplayIcon = "$($script:Programs)\uninstallerIcon.ico"; UninstallString = "`"$($script:Programs)\Uninstall Jan.exe`" /currentuser"
            }
        }
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(@{ Path = $script:Machine; Scope = 'Machine'; Architecture = 'X64' }, @{ Path = $script:User; Scope = 'User'; Architecture = $null })
        }
        # reg.exe nachbilden: schreibt eine Sicherung wie reg export (UTF-16 mit Schlüsselzeile)
        $script:ExportMode = 'Good'
        Mock -ModuleName SoftwareInventory Invoke-RegExport {
            switch ($script:ExportMode) {
                'Good' { "Windows Registry Editor Version 5.00`r`n`r`n[$NativeKey]`r`n`"DisplayName`"=`"Jan 0.5.16`"`r`n" | Set-Content -LiteralPath $File -Encoding Unicode; 0 }
                'Empty' { [System.IO.File]::WriteAllBytes($File, [byte[]] @()); 0 }
                'WrongKey' { "Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Other]`r`n" | Set-Content -LiteralPath $File -Encoding Unicode; 0 }
                'None' { 0 }
                'ExitCode' { 1 }
            }
        }
        function Get-Orphan([string] $Root = $script:User) {
            $scope = if ($Root -like '*User') { 'User' } else { 'Machine' }
            InModuleScope SoftwareInventory -Parameters @{ R = $Root; S = $scope } {
                Get-RegistrySoftware -Location @(@{ Path = $R; Scope = $S; Architecture = $null })
            } | Where-Object Name -EQ 'Jan 0.5.16'
        }
    }

    It 'plant mit -WhatIf, ohne etwas zu ändern' {
        $r = Get-Orphan | Remove-OrphanedEntry -WhatIf
        $r.Result | Should -Be 'Planned'
        $r.Action | Should -Be 'RemoveEntry'
        $r.CommandLine | Should -BeLike 'HKEY_CURRENT_USER\*\RemoveUser\janold'
        $r.Message.Code | Should -Be 'PlanRemoveEntry'
        Test-Path "$($script:User)\janold" | Should -BeTrue
        Should -Invoke -ModuleName SoftwareInventory Invoke-RegExport -Times 0 -Exactly
    }

    It 'sichert, prüft die Sicherung, entfernt nur den Schlüssel und protokolliert' {
        $plan = Get-Orphan | Remove-OrphanedEntry -WhatIf
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
        $r.Result | Should -Be 'Succeeded'
        $r.Message.Code | Should -Be 'RemoveEntryDone'
        Test-Path "$($script:User)\janold" | Should -BeFalse
        Test-Path $script:Programs | Should -BeTrue -Because 'Ordner werden nie gelöscht'
        $backup = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\registry-backup') -File
        $backup.Name | Should -Be "$($r.ActionId)_Jan_0.5.16.reg"
        $r.BackupFile | Should -Be $backup.FullName
        $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
        $log.Phase | Should -Be @('Started', 'Completed')
        $log[1].Action | Should -Be 'RemoveEntry'
        $log[1].Result | Should -Be 'Succeeded'
    }

    It 'entfernt nichts, wenn die Sicherung nicht passt (<Mode>)' -TestCases @(
        @{ Mode = 'Empty'; Expected = 'Empty' }
        @{ Mode = 'WrongKey'; Expected = 'KeyNotFound' }
        @{ Mode = 'None'; Expected = 'Missing' }
        @{ Mode = 'ExitCode'; Expected = 'Missing' }
    ) {
        $script:ExportMode = $Mode
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryBackupInvalid'
        $r.Message.Args[0] | Should -Be $Expected
        Test-Path "$($script:User)\janold" | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\registry-backup') -File -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'prüft direkt davor neu und entfernt nichts, wenn der Eintrag nicht mehr verwaist ist' {
        $record = Get-Orphan
        'x' | Set-Content (Join-Path $script:Programs 'Uninstall Jan.exe')
        $r = $record | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Unsupported'
        $r.Message.Code | Should -Be 'RemoveEntryNotOrphaned'
        Test-Path "$($script:User)\janold" | Should -BeTrue
        Should -Invoke -ModuleName SoftwareInventory Invoke-RegExport -Times 0 -Exactly
    }

    It 'lässt Einträge für alle Benutzer (HKLM) vorerst stehen' {
        $r = Get-Orphan -Root $script:Machine | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Unsupported'
        $r.Message.Code | Should -Be 'RemoveEntryMachineNotYet'
        Test-Path "$($script:Machine)\janold" | Should -BeTrue
    }

    It 'lehnt Schlüssel außerhalb der Uninstall-Zweige ab' {
        $record = Get-Orphan
        $record.RegistryKey = 'TestRegistry:\Elsewhere\janold'
        ($record | Remove-OrphanedEntry -Confirm:$false).Message.Code | Should -Be 'RemoveEntryNotUninstallKey'
    }

    It 'bricht ab, wenn sich der bestätigte Schlüssel geändert hat' {
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedCommandLine 'HKEY_CURRENT_USER\anders'
        $r.Result | Should -Be 'Cancelled'
        Test-Path "$($script:User)\janold" | Should -BeTrue
    }

    It 'bildet den Dateinamen aus ActionId und bereinigtem Programmnamen' {
        InModuleScope SoftwareInventory {
            Get-RegistryBackupFileName -ActionId 'id' -Name 'Jan 0.5.16' | Should -Be 'id_Jan_0.5.16.reg'
            Get-RegistryBackupFileName -ActionId 'id' -Name 'A/B: C*?' | Should -Be 'id_A_B_C.reg'
            Get-RegistryBackupFileName -ActionId 'id' -Name '???' | Should -Be 'id_Eintrag.reg'
        }
    }
}

Describe 'Sicherung mit dem echten reg.exe' {
    It 'erkennt eine echte reg-export-Datei als brauchbar' {
        $key = New-Item -Path 'TestRegistry:\RealExport\janold' -Force
        New-ItemProperty -Path $key.PSPath -Name DisplayName -Value 'Jan 0.5.16' | Out-Null
        $file = Join-Path $TestDrive 'real.reg'
        InModuleScope SoftwareInventory -Parameters @{ K = $key.Name; F = $file } {
            Invoke-RegExport -NativeKey $K -File $F | Should -Be 0
            Test-RegistryBackup -File $F -NativeKey $K | Should -BeNullOrEmpty
            Test-RegistryBackup -File $F -NativeKey 'HKEY_CURRENT_USER\Software\Anderer' | Should -Be 'KeyNotFound'
        }
    }
}

Describe 'Sicherungen entfernter Einträge in der Selbstbereinigung' {
    It 'behält Sicherungen bis 365 Tage, auch über der Größengrenze, und löscht ältere' {
        $root = Join-Path $TestDrive 'cleanup'
        $backup = Join-Path $root 'logs\registry-backup'
        $actions = Join-Path $root 'logs\actions'
        New-Item -ItemType Directory -Path $backup, $actions -Force | Out-Null
        $old = Join-Path $backup 'old.reg'; $recent = Join-Path $backup 'recent.reg'; $big = Join-Path $backup 'big.reg'; $log = Join-Path $actions 'old.jsonl'
        'x' | Set-Content -LiteralPath $old, $recent, $log
        [System.IO.File]::WriteAllBytes($big, [byte[]]::new(2MB))
        (Get-Item $old).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-400)
        (Get-Item $recent).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-100)
        (Get-Item $big).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
        (Get-Item $log).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-40)
        InModuleScope SoftwareInventory -Parameters @{ R = $root } { Invoke-AppDataCleanup -RetentionDays 30 -MaxSizeMB 1 -Root $R } | Out-Null
        Test-Path $old | Should -BeFalse
        Test-Path $recent | Should -BeTrue
        Test-Path $big | Should -BeTrue -Because 'Sicherungen zählen nicht zur Größengrenze'
        Test-Path $log | Should -BeFalse -Because 'Logs daneben werden normal bereinigt'
    }
}
