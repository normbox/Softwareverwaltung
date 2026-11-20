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
                'Subkey' { "Windows Registry Editor Version 5.00`r`n`r`n[$NativeKey]`r`n`"DisplayName`"=`"Jan 0.5.16`"`r`n`r`n[$NativeKey\Sub]`r`n`"A`"=`"1`"`r`n" | Set-Content -LiteralPath $File -Encoding Unicode; 0 }
                'ForeignSub' { "Windows Registry Editor Version 5.00`r`n`r`n[$NativeKey]`r`n`r`n[${NativeKey}X]`r`n" | Set-Content -LiteralPath $File -Encoding Unicode; 0 }
                'Ansi' { "Windows Registry Editor Version 5.00`r`n`r`n[$NativeKey]`r`n" | Set-Content -LiteralPath $File -Encoding ascii; 0 }
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
        $backup = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\registry-backup') -File -Filter '*.reg'
        $backup.Name | Should -Be "$($r.ActionId)_Jan_0.5.16.reg"
        $r.BackupFile | Should -Be $backup.FullName
        $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
        $log.Phase | Should -Be @('Started', 'Completed')
        $log[1].Action | Should -Be 'RemoveEntry'
        $log[1].Result | Should -Be 'Succeeded'
    }

    Context 'bestätigte Kennung (ConfirmedActionId)' {
        BeforeEach {
            # Test-ActionIdUsed liest beide Sicherungsordner: nie den echten Admin-Ordner unter Program Files.
            Mock -ModuleName SoftwareInventory Get-RegistryBackupMachineDirectory { Join-Path $script:AppDir 'machine-backup' }
        }

        It 'legt die Sicherung unter genau der Kennung an, die der Dialog gezeigt hat' {
            $plan = Get-Orphan | Remove-OrphanedEntry -WhatIf
            $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedCommandLine $plan.CommandLine -ConfirmedActionId $plan.ActionId
            $r.Result | Should -Be 'Succeeded'
            $r.ActionId | Should -Be $plan.ActionId
            $r.BackupFile | Should -Be $plan.Message.Args[1] -Because 'der Dialog nennt genau diese Datei'
            Test-Path -LiteralPath $plan.Message.Args[1] | Should -BeTrue
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            @($log.ActionId | Select-Object -Unique) | Should -Be @($plan.ActionId)
        }

        It 'bricht ab, ohne etwas zu ändern, wenn die Kennung <Case>' -TestCases @(
            @{ Case = 'keine GUID ist'; Mode = 'Invalid'; Code = 'ActionIdInvalid' }
            @{ Case = 'schon im Protokoll steht'; Mode = 'Logged'; Code = 'ActionIdUsed' }
            @{ Case = 'schon eine Sicherung benennt'; Mode = 'File'; Code = 'ActionIdUsed' }
        ) {
            $id = [guid]::NewGuid().ToString()
            switch ($Mode) {
                'Invalid' { $id = 'keine-guid' }
                'Logged' {
                    $dir = Join-Path $script:AppDir 'logs\actions'; New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $dir 'actions-alt.jsonl') -Value "{`"ActionId`":`"$($id.ToUpperInvariant())`",`"Phase`":`"Completed`"}"
                }
                'File' {
                    $dir = Join-Path $script:AppDir 'logs\registry-backup'; New-Item -ItemType Directory -Path $dir -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $dir "${id}_Jan_0.5.16.json") -Value '{}'
                }
            }
            $plan = Get-Orphan | Remove-OrphanedEntry -WhatIf
            $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedCommandLine $plan.CommandLine -ConfirmedActionId $id
            $r.Result | Should -Be 'Cancelled'
            $r.Message.Code | Should -Be $Code
            $r.ActionId | Should -Not -Be $id -Because 'der Abbruch wird unter einer neuen Kennung protokolliert'
            Test-Path "$($script:User)\janold" | Should -BeTrue
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegExport -Times 0 -Exactly
        }

        It 'lässt eine Kennung nicht zweimal ausführen' {
            $plan = Get-Orphan | Remove-OrphanedEntry -WhatIf
            (Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedActionId $plan.ActionId).Result | Should -Be 'Succeeded'
            # Derselbe Eintrag taucht wieder auf (z. B. zurückgespielt): dieselbe Kennung darf nicht noch einmal laufen.
            New-UninstallKey $script:User 'janold' @{
                DisplayName = 'Jan 0.5.16'; DisplayVersion = '0.5.16'; Publisher = 'Jan'
                DisplayIcon = "$($script:Programs)\uninstallerIcon.ico"; UninstallString = "`"$($script:Programs)\Uninstall Jan.exe`" /currentuser"
            }
            $again = Get-Orphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedActionId $plan.ActionId
            $again.Result | Should -Be 'Cancelled'
            $again.Message.Code | Should -Be 'ActionIdUsed'
            Test-Path "$($script:User)\janold" | Should -BeTrue
            @(Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\registry-backup') -Filter '*.reg').Count | Should -Be 1
        }
    }

    It 'entfernt nichts, wenn die Sicherung nicht passt (<Mode>)' -TestCases @(
        @{ Mode = 'Empty'; Expected = 'Empty' }
        @{ Mode = 'WrongKey'; Expected = 'KeyMismatch' }
        @{ Mode = 'ForeignSub'; Expected = 'KeyOutside' }
        @{ Mode = 'Ansi'; Expected = 'BadEncoding' }
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

    It 'schreibt neben die Sicherung eine Begleitdatei mit Codes statt Texten' {
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        $sidecar = [System.IO.Path]::ChangeExtension($r.BackupFile, '.json')
        Test-Path -LiteralPath $sidecar | Should -BeTrue
        $raw = Get-Content -LiteralPath $sidecar -Raw
        $raw | Should -Not -Match '"Text"'
        $json = $raw | ConvertFrom-Json
        $json.SchemaVersion | Should -Be 1
        $json.ActionId | Should -Be $r.ActionId
        $json.Name | Should -Be 'Jan 0.5.16'
        $json.NativeKey | Should -BeLike 'HKEY_CURRENT_USER\*\RemoveUser\janold'
        $json.Scope | Should -Be 'User'
        @($json.Reasons.Code) | Should -Be @('OrphanedEntry')
    }

    It 'übernimmt nur bekannte Gründe vom Eingabeobjekt' {
        $rating = [pscustomobject] @{
            Record  = Get-Orphan
            Reasons = @(
                [pscustomobject] @{ Code = 'NewerInstallNextTo'; Args = @('Jan', '0.8.8') }
                [pscustomobject] @{ Code = 'Unbekannt'; Args = @('x') }
            )
        }
        $r = $rating | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        $json = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($r.BackupFile, '.json')) -Raw | ConvertFrom-Json
        @($json.Reasons.Code) | Should -Be @('OrphanedEntry', 'NewerInstallNextTo')
        @($json.Reasons[1].Args) | Should -Be @('Jan', '0.8.8')
    }

    It 'verwirft Gründe mit falscher Argumentzahl, die Sicherung bleibt zurückspielbar' {
        # Vorher schrieb NewerInstallNextTo mit ('Jan', $null) eine Sicherung, die beim Lesen sofort ungültig war.
        Mock -ModuleName SoftwareInventory Get-RegistryBackupMachineDirectory { Join-Path $script:AppDir 'ProgramFiles\RegistryBackup' }
        $rating = [pscustomobject] @{
            Record  = Get-Orphan
            Reasons = @(
                [pscustomobject] @{ Code = 'OrphanedEntry'; Args = @() }
                [pscustomobject] @{ Code = 'NewerInstallNextTo'; Args = @('Jan', $null) }
                [pscustomobject] @{ Code = 'NewerInstallNextTo'; Args = @('Jan', '0.8.8', 'zu viel') }
            )
        }
        $r = $rating | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        $json = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($r.BackupFile, '.json')) -Raw | ConvertFrom-Json
        @($json.Reasons.Code) | Should -Be @('OrphanedEntry')
        $item = @(Get-RegistryBackup) | Where-Object Id -EQ $r.ActionId
        $item.Problem | Should -BeNullOrEmpty
        $item.CanRestore | Should -BeTrue
        (Restore-RegistryBackup $r.ActionId -WhatIf).Result | Should -Be 'Planned'
    }

    It 'entfernt auch einen Schlüssel mit Unterschlüsseln, wenn die Sicherung ihn vollständig enthält' {
        New-Item -Path "$($script:User)\janold\Sub" -Force | Out-Null
        $script:ExportMode = 'Subkey'
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        Test-Path "$($script:User)\janold" | Should -BeFalse
    }

    It 'entfernt nichts, wenn die Begleitdatei nicht geschrieben werden kann' {
        Mock -ModuleName SoftwareInventory Write-RegistryBackupSidecar { throw 'Datenträger voll' }
        $r = Get-Orphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryBackupInvalid'
        $r.Message.Args[0] | Should -Be 'MetadataWrite'
        Test-Path "$($script:User)\janold" | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\registry-backup') -File -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
    }

    It 'lehnt Schlüsselnamen mit [ ] oder Steuerzeichen schon bei der Planung ab (<Name>)' -ForEach @(
        @{ Name = 'eckige Klammern'; Leaf = 'jan[1]' }
        @{ Name = 'nur ]'; Leaf = 'jan]' }
        @{ Name = 'Anführungszeichen'; Leaf = 'jan"x' }
        @{ Name = 'Tabulator'; Leaf = "jan`tx" }
        @{ Name = 'U+0001'; Leaf = "jan$([char] 1)x" }
        @{ Name = 'U+007F'; Leaf = "jan$([char] 127)x" }
        @{ Name = 'U+0080'; Leaf = "jan$([char] 128)x" }
    ) {
        $record = Get-Orphan
        $record.RegistryKey = "$($script:User)\$Leaf"
        $r = $record | Remove-OrphanedEntry -WhatIf
        $r.Result | Should -Be 'Unsupported'
        $r.Message.Code | Should -Be 'BackupKeyNameUnsafe'
        Should -Invoke -ModuleName SoftwareInventory Invoke-RegExport -Times 0 -Exactly
    }

    It 'bildet den Dateinamen aus ActionId und bereinigtem Programmnamen' {
        InModuleScope SoftwareInventory {
            Get-RegistryBackupFileName -ActionId 'id' -Name 'Jan 0.5.16' | Should -Be 'id_Jan_0.5.16.reg'
            Get-RegistryBackupFileName -ActionId 'id' -Name 'A/B: C*?' | Should -Be 'id_A_B_C.reg'
            Get-RegistryBackupFileName -ActionId 'id' -Name '???' | Should -Be 'id_Eintrag.reg'
        }
    }

    It 'härtet den Dateinamen: keine Pfadzeichen, kein "..", keine reservierten Namen, begrenzte Länge' -TestCases @(
        @{ Name = '..\..\evil'; Expected = 'id_evil.reg' }
        @{ Name = '../../Windows/x'; Expected = 'id_Windows_x.reg' }
        @{ Name = 'a..b'; Expected = 'id_a.b.reg' }
        @{ Name = 'C:\Temp\x'; Expected = 'id_C_Temp_x.reg' }
        @{ Name = 'CON'; Expected = 'id__CON.reg' }
        @{ Name = 'nul.txt'; Expected = 'id__nul.txt.reg' }
        @{ Name = 'COM1'; Expected = 'id__COM1.reg' }
        @{ Name = ('a' * 200); Expected = "id_$('a' * 60).reg" }
    ) {
        InModuleScope SoftwareInventory -Parameters @{ N = $Name; E = $Expected } {
            $f = Get-RegistryBackupFileName -ActionId 'id' -Name $N
            $f | Should -Be $E
            $f | Should -Not -Match '[\\/:]'
            $f | Should -Not -Match '\.\.'
        }
    }
}

Describe 'Remove-OrphanedEntry für alle Benutzer (HKLM über den Helfer)' {
    BeforeEach {
        $script:AppDir = Join-Path $TestDrive "app-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $script:AppDir }
        $script:Programs = Join-Path $TestDrive 'ProgM'
        New-Item -ItemType Directory -Path $script:Programs -Force | Out-Null
        # Nachbildung der beiden HKLM-Zweige unter TestRegistry; der 32-Bit-Zweig trägt WOW6432Node im Pfad wie in HKLM.
        $script:Machine = 'TestRegistry:\M64'
        $script:Machine32 = 'TestRegistry:\WOW6432Node\M32'
        Remove-Item -LiteralPath 'TestRegistry:\M64', 'TestRegistry:\WOW6432Node' -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:Machine, $script:Machine32 -Force | Out-Null
        foreach ($root in $script:Machine, $script:Machine32) {
            New-UninstallKey $root 'janold' @{
                DisplayName = 'Jan 0.5.16'; DisplayVersion = '0.5.16'; Publisher = 'Jan'
                UninstallString = "`"$($script:Programs)\Uninstall Jan.exe`" /S"
            }
        }
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(@{ Path = $script:Machine; Scope = 'Machine'; Architecture = 'X64' }, @{ Path = $script:Machine32; Scope = 'Machine'; Architecture = 'X86' })
        }
        Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $false }
        Mock -ModuleName SoftwareInventory Invoke-RegExport { throw 'HKLM sichert nur der Helfer' }
        # Die Prüfung „Schlüssel weg“ liest im Modul HKLM in der 64-Bit-Ansicht; hier gegen die Nachbildung.
        Mock -ModuleName SoftwareInventory Test-MachineRegistryKeyPresent { Test-Path -LiteralPath $RegistryKey }
        # Der Helfer: Standard = sichert am geplanten Ort und löscht den Schlüssel.
        $script:HelperMode = 'Removed'
        Mock -ModuleName SoftwareInventory Start-ElevatedHelper {
            $planned = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) "Softwareverwaltung\RegistryBackup\$($HelperPlan.ActionId).reg"
            $message = { param($Code) [pscustomobject] @{ Code = $Code; Args = @(); Text = $Code } }
            switch ($script:HelperMode) {
                'Removed' { Remove-Item -LiteralPath $HelperPlan.RegistryKey -Recurse -Force; @{ Status = 'Completed'; Removed = $true; BackupFile = $planned; Error = $null } }
                'Denied' { @{ Status = 'ElevationDenied'; Error = (& $message 'ElevationDenied') } }
                'TooOld' { @{ Status = 'Failed'; Error = (& $message 'HelperTooOld') } }
                'FolderWritable' { @{ Status = 'Completed'; Removed = $false; BackupFile = $null; ErrorCode = 'BackupFolderWritable'; Error = (& $message 'BackupFolderWritable') } }
                'OtherPath' { Remove-Item -LiteralPath $HelperPlan.RegistryKey -Recurse -Force; @{ Status = 'Completed'; Removed = $true; BackupFile = 'C:\Users\x\evil.reg'; Error = $null } }
                'ClaimsRemoved' { @{ Status = 'Completed'; Removed = $true; BackupFile = $planned; Error = $null } }
                'DeleteFailed' { @{ Status = 'Completed'; Removed = $false; BackupFile = $planned; ErrorCode = 'RemoveEntryDeleteFailed'; Error = (& $message 'RemoveEntryDeleteFailed') } }
                'NoRemovedField' { @{ Status = 'Completed'; BackupFile = $planned; Error = $null } }
                'RemovedAsText' { @{ Status = 'Completed'; Removed = 'true'; BackupFile = $planned; Error = $null } }
                'Throws' { throw 'Helfer nicht startbar' }
                'Lost' { Remove-Item -LiteralPath $HelperPlan.RegistryKey -Recurse -Force; @{ Status = 'Failed'; Error = (& $message 'HelperResultIncomplete') } }
            }
        }
        function Get-MachineOrphan([string] $Root = $script:Machine, [string] $Architecture = 'X64') {
            InModuleScope SoftwareInventory -Parameters @{ R = $Root; A = $Architecture } {
                Get-RegistrySoftware -Location @(@{ Path = $R; Scope = 'Machine'; Architecture = $A })
            } | Where-Object Name -EQ 'Jan 0.5.16'
        }
    }

    It 'plant mit -WhatIf für alle Benutzer: Administratorrechte, Sicherung im Admin-Ordner, kein Helfer' {
        $r = Get-MachineOrphan | Remove-OrphanedEntry -WhatIf
        $r.Result | Should -Be 'Planned'
        $r.Elevated | Should -BeTrue
        $r.Message.Code | Should -Be 'PlanRemoveEntryMachine'
        $r.Message.Args[1] | Should -Be (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) "Softwareverwaltung\RegistryBackup\$($r.ActionId).reg")
        Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 0 -Exactly
        Test-Path "$($script:Machine)\janold" | Should -BeTrue
    }

    It 'schickt dem Helfer nur Schlüssel, ActionId und bekannte Gründe, ohne Wiederherstellungspunkt, und meldet Erfolg' {
        $record = Get-MachineOrphan
        $record | Add-Member -NotePropertyName Reasons -NotePropertyValue @(@{ Code = 'NewerInstallNextTo'; Args = @('Jan', '0.8.8') }, @{ Code = 'NewerInstallNextTo'; Args = @('Nur eins') }, @{ Code = 'Erfunden'; Args = @() }) -Force
        $r = $record | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        $r.Message.Code | Should -Be 'RemoveEntryDoneMachine'
        $r.BackupFile | Should -BeLike "*\Softwareverwaltung\RegistryBackup\$($r.ActionId).reg"
        $r.PresentAfter | Should -BeFalse
        Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -Exactly -ParameterFilter {
            $HelperPlan.Operation -ceq 'RemoveRegistryEntry' -and $HelperPlan.RestorePoint -eq $false -and -not $HelperPlan.ContainsKey('FilePath') -and
            $HelperPlan.RegistryKey -eq "$($script:Machine)\janold" -and $HelperPlan.ActionId -match '^[0-9a-f-]{36}$' -and
            (@($HelperPlan.Reasons.Code) -join ',') -ceq 'OrphanedEntry,NewerInstallNextTo'
        }
        Should -Invoke -ModuleName SoftwareInventory Invoke-RegExport -Times 0 -Exactly
        $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
        $log.Phase | Should -Be @('Started', 'Completed')
        $log[1].Result | Should -Be 'Succeeded'
    }

    It 'gibt dem Helfer die bestätigte Kennung, damit die Sicherung so heißt wie im Dialog' {
        # Der Helfer-Nachbau rechnet mit dem echten Admin-Pfad; die Prüfung „schon benutzt“ (liest die Ordner) ist anderswo getestet.
        Mock -ModuleName SoftwareInventory Test-ActionIdUsed { $false }
        $plan = Get-MachineOrphan | Remove-OrphanedEntry -WhatIf
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false -ConfirmedCommandLine $plan.CommandLine -ConfirmedActionId $plan.ActionId
        $r.ActionId | Should -Be $plan.ActionId
        $r.BackupFile | Should -Be $plan.Message.Args[1]
        Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -Exactly -ParameterFilter { $HelperPlan.ActionId -ceq $plan.ActionId }
    }

    It 'prüft bei einem 32-Bit-Eintrag (WOW6432Node) genau diesen Schlüssel, wie der Helfer' {
        $r = Get-MachineOrphan -Root $script:Machine32 -Architecture 'X86' | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Succeeded'
        Should -Invoke -ModuleName SoftwareInventory Start-ElevatedHelper -Times 1 -Exactly -ParameterFilter { $HelperPlan.RegistryKey -eq "$($script:Machine32)\janold" }
        Should -Invoke -ModuleName SoftwareInventory Test-MachineRegistryKeyPresent -Times 1 -Exactly -ParameterFilter { $RegistryKey -eq "$($script:Machine32)\janold" }
        Test-Path "$($script:Machine)\janold" | Should -BeTrue -Because 'der 64-Bit-Eintrag gleichen Namens bleibt unberührt'
    }

    It 'meldet <Mode> ehrlich und lässt den Schlüssel stehen' -TestCases @(
        @{ Mode = 'Denied'; Result = 'ElevationDenied'; Code = 'ElevationDenied'; Backup = $false }
        @{ Mode = 'TooOld'; Result = 'Failed'; Code = 'HelperTooOld'; Backup = $false }
        @{ Mode = 'FolderWritable'; Result = 'Failed'; Code = 'BackupFolderWritable'; Backup = $false }
        @{ Mode = 'ClaimsRemoved'; Result = 'Failed'; Code = 'RemoveEntryDeleteFailedBackupKept'; Backup = $true }
        @{ Mode = 'DeleteFailed'; Result = 'Failed'; Code = 'RemoveEntryDeleteFailedBackupKept'; Backup = $true }
    ) {
        $script:HelperMode = $Mode
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be $Result
        $r.Message.Code | Should -Be $Code
        [bool] $r.BackupFile | Should -Be $Backup
        $r.PresentAfter | Should -BeTrue
        Test-Path "$($script:Machine)\janold" | Should -BeTrue
    }

    It 'zählt ein Ergebnis ohne echtes Removed nie als Erfolg (<Mode>)' -TestCases @(@{ Mode = 'NoRemovedField' }, @{ Mode = 'RemovedAsText' }) {
        $script:HelperMode = $Mode
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'HelperResultUnreadable'
        Test-Path "$($script:Machine)\janold" | Should -BeTrue
    }

    It 'meldet einen Helfer, der nicht startet, als Fehler und protokolliert' {
        $script:HelperMode = 'Throws'
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryDeleteFailed'
        $r.BackupFile | Should -BeNullOrEmpty
        $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
        $log.Phase | Should -Be @('Started', 'Completed')
    }

    It 'meldet eine verlorene Antwort als unklar mit dem Ort der Sicherung, nie als Erfolg' {
        $script:HelperMode = 'Lost'
        # Nur die geplante Sicherung unter Program Files „gibt es“; alle anderen Aufrufe gehen an das echte Test-Path.
        Mock -ModuleName SoftwareInventory Test-Path { Microsoft.PowerShell.Management\Test-Path @PesterBoundParameters }
        Mock -ModuleName SoftwareInventory Test-Path { $true } -ParameterFilter { $LiteralPath -like '*\Softwareverwaltung\RegistryBackup\*.reg' }
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryResultUnclear'
        $r.BackupFile | Should -BeLike "*\RegistryBackup\$($r.ActionId).reg"
        $r.PresentAfter | Should -BeFalse
    }

    It 'zählt einen nicht lesbaren Schlüssel danach nie als entfernt' {
        Mock -ModuleName SoftwareInventory Test-MachineRegistryKeyPresent { throw [System.Security.SecurityException]::new('verweigert') }
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryDeleteFailedBackupKept'
        $r.BackupFile | Should -BeLike "*\RegistryBackup\$($r.ActionId).reg"
    }

    It 'reicht HelperInWritableFolder in den Plan weiter' {
        Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $true }
        (Get-MachineOrphan | Remove-OrphanedEntry -WhatIf).HelperInWritableFolder | Should -BeTrue
    }

    It 'verlangt für RemoveRegistryEntry mindestens Helferversion 6' {
        InModuleScope SoftwareInventory { $script:HelperOperationMinVersion['RemoveRegistryEntry'] | Should -Be 6 }
    }

    It 'zählt eine Sicherung an einem anderen als dem geplanten Ort nie als Erfolg' {
        $script:HelperMode = 'OtherPath'
        $r = Get-MachineOrphan | Remove-OrphanedEntry -Confirm:$false
        $r.Result | Should -Be 'Failed'
        $r.Message.Code | Should -Be 'RemoveEntryBackupUnexpected'
        $r.BackupFile | Should -BeNullOrEmpty
    }
}

Describe 'Test-MachineRegistryKeyPresent (64-Bit-Ansicht wie der Helfer)' {
    It 'findet vorhandene Schlüssel im 64-Bit-Zweig und unter WOW6432Node, nur lesend' {
        InModuleScope SoftwareInventory {
            Test-MachineRegistryKeyPresent -RegistryKey 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | Should -BeTrue
            Test-MachineRegistryKeyPresent -RegistryKey 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | Should -BeTrue
            Test-MachineRegistryKeyPresent -RegistryKey 'HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' | Should -BeTrue
        }
    }

    It 'lehnt Pfade ohne HKLM-Präfix ab, statt sie als „nicht vorhanden“ zu werten' {
        InModuleScope SoftwareInventory {
            { Test-MachineRegistryKeyPresent -RegistryKey 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' } | Should -Throw
            { Test-MachineRegistryKeyPresent -RegistryKey 'TestRegistry:\x' } | Should -Throw
            { Test-MachineRegistryKeyPresent -RegistryKey 'HKLM:\' } | Should -Throw
        }
    }

    It 'meldet fehlende Schlüssel in beiden Zweigen als nicht vorhanden' {
        $name = "SWV-gibt-es-nicht-$([guid]::NewGuid().ToString('N'))"
        InModuleScope SoftwareInventory -Parameters @{ N = $name } {
            Test-MachineRegistryKeyPresent -RegistryKey "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$N" | Should -BeFalse
            Test-MachineRegistryKeyPresent -RegistryKey "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\$N" | Should -BeFalse
        }
    }
}

Describe 'Test-RegistryBackupContent (strenge Prüfung)' {
    BeforeAll {
        New-Item -Path 'TestRegistry:\ValUser', 'TestRegistry:\ValMachine', 'TestRegistry:\ValElsewhere' -Force | Out-Null
        $script:UserNative = (Get-Item 'TestRegistry:\ValUser').Name
        $script:MachineNative = (Get-Item 'TestRegistry:\ValMachine').Name
        $script:ElsewhereNative = (Get-Item 'TestRegistry:\ValElsewhere').Name
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(@{ Path = 'TestRegistry:\ValMachine'; Scope = 'Machine'; Architecture = 'X64' }, @{ Path = 'TestRegistry:\ValUser'; Scope = 'User'; Architecture = $null })
        }
        function New-RegText([string[]] $Keys, [string] $Header = 'Windows Registry Editor Version 5.00') {
            "$Header`r`n`r`n" + (($Keys | ForEach-Object { "[$_]`r`n`"DisplayName`"=`"x`"`r`n" }) -join "`r`n")
        }
        function Test-Content([string] $Text, [string] $Key) {
            InModuleScope SoftwareInventory -Parameters @{ T = $Text; K = $Key } { Test-RegistryBackupContent -Text $T -NativeKey $K }
        }
    }

    It 'akzeptiert genau einen Hauptschlüssel unter dem Uninstall-Zweig des Benutzers' {
        $key = "$($script:UserNative)\App"
        Test-Content (New-RegText $key) $key | Should -BeNullOrEmpty
    }

    It 'akzeptiert Unterschlüssel des Hauptschlüssels, auch tief verschachtelt' {
        $key = "$($script:UserNative)\App"
        Test-Content (New-RegText $key, "$key\Sub", "$key\Sub\Deep") $key | Should -BeNullOrEmpty
    }

    It 'lehnt ab: <Case>' -TestCases @(
        @{ Case = 'Schlüssel außerhalb des Hauptschlüssels'; Zone = 'User'; Keys = @('App', 'Other'); Main = 'App'; Expected = 'KeyOutside' }
        @{ Case = 'Präfix-Trick (App gegen AppX)'; Zone = 'User'; Keys = @('App', 'AppX'); Main = 'App'; Expected = 'KeyOutside' }
        @{ Case = 'Hauptschlüssel zweimal'; Zone = 'User'; Keys = @('App', 'App'); Main = 'App'; Expected = 'KeyOutside' }
        @{ Case = 'anderer Schlüssel zuerst'; Zone = 'User'; Keys = @('Other', 'App'); Main = 'App'; Expected = 'KeyMismatch' }
        @{ Case = 'Hauptschlüssel außerhalb der Uninstall-Zweige'; Zone = 'Elsewhere'; Keys = @('App'); Main = 'App'; Expected = 'KeyNotUninstall' }
        @{ Case = 'Eintrag für alle Benutzer (HKLM)'; Zone = 'Machine'; Keys = @('App'); Main = 'App'; Expected = 'MachineKeyInUserBackup' }
        @{ Case = 'Hauptschlüssel eine Ebene zu tief'; Zone = 'User'; Keys = @('App\Sub'); Main = 'App\Sub'; Expected = 'KeyNotUninstall' }
    ) {
        $base = switch ($Zone) { 'User' { $script:UserNative } 'Machine' { $script:MachineNative } default { $script:ElsewhereNative } }
        $keys = @($Keys | ForEach-Object { "$base\$_" })
        Test-Content (New-RegText $keys) "$base\$Main" | Should -Be $Expected
    }

    It 'lehnt Löschzeilen ab, auch mit Leerzeichen davor' {
        $key = "$($script:UserNative)\App"
        Test-Content ((New-RegText $key) + "`r`n[-$($script:UserNative)\Anderes]`r`n") $key | Should -Be 'DeleteLine'
        Test-Content ((New-RegText $key) + "`r`n  [-$($script:UserNative)\Anderes]`r`n") $key | Should -Be 'DeleteLine'
    }

    It 'lehnt einen falschen Kopf, fehlende Schlüssel und kaputte Schlüsselzeilen ab' {
        $key = "$($script:UserNative)\App"
        Test-Content (New-RegText $key 'REGEDIT4') $key | Should -Be 'BadHeader'
        Test-Content "Windows Registry Editor Version 5.00`r`n`r`n`"A`"=`"1`"`r`n" $key | Should -Be 'KeyNotFound'
        Test-Content "Windows Registry Editor Version 5.00`r`n`r`n[$key" $key | Should -Be 'BadKeyLine'
        Test-Content '' $key | Should -Be 'Empty'
    }

    It 'lehnt ungewöhnliche Zeilenumbrüche ab (<Case>), damit sich keine Schlüsselzeile verstecken kann' -TestCases @(
        @{ Case = 'einzelnes CR'; Sep = "`r" }
        @{ Case = 'einzelnes LF'; Sep = "`n" }
        @{ Case = 'NUL'; Sep = "`0" }
        @{ Case = 'Zeilentrenner U+2028'; Sep = [string][char]0x2028 }
        @{ Case = 'Zeilentrenner U+0085'; Sep = [string][char]0x0085 }
    ) {
        $key = "$($script:UserNative)\App"
        $hidden = "$($script:UserNative)\Run"
        Test-Content ((New-RegText $key) + $Sep + "[$hidden]`r`n") $key | Should -Be 'BadLineBreak'
    }

    It 'Groß-/Kleinschreibung des Schlüssels spielt keine Rolle' {
        $key = "$($script:UserNative)\App"
        Test-Content (New-RegText $key.ToUpperInvariant()) $key | Should -BeNullOrEmpty
    }
}

Describe 'Begleitdatei einer Sicherung' {
    BeforeEach {
        $script:Dir = Join-Path $TestDrive "backup-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        New-Item -ItemType Directory -Path $script:Dir | Out-Null
        $script:Id = [guid]::NewGuid().ToString()
        $script:Reg = Join-Path $script:Dir "$($script:Id)_Jan.reg"
        'x' | Set-Content -LiteralPath $script:Reg
    }

    It 'wird geschrieben und gelesen; unbekannte Gründe fallen weg, Args werden gekürzt' {
        InModuleScope SoftwareInventory -Parameters @{ F = $script:Reg; I = $script:Id } {
            $reasons = @(
                [pscustomobject] @{ Code = 'OrphanedEntry'; Args = @() }
                [pscustomobject] @{ Code = 'NewerInstallNextTo'; Args = @('Jan', ('9' * 500)) }
                [pscustomobject] @{ Code = 'Boese'; Args = @('x') }
            )
            Write-RegistryBackupSidecar -File $F -ActionId $I -Name 'Jan' -NativeKey 'HKEY_CURRENT_USER\x' -Scope 'User' -Reasons $reasons
            $read = Read-RegistryBackupSidecar -File $F
            $read.Problem | Should -BeNullOrEmpty
            $read.Data.Name | Should -Be 'Jan'
            $read.Data.CreatedAt.Kind | Should -Be 'Utc'
            @($read.Data.Reasons.Code) | Should -Be @('OrphanedEntry', 'NewerInstallNextTo')
            $read.Data.Reasons[1].Args[1].Length | Should -Be 200
        }
    }

    It 'meldet fehlende, kaputte und nicht zur Datei passende Begleitdateien' {
        InModuleScope SoftwareInventory -Parameters @{ F = $script:Reg; I = $script:Id } {
            (Read-RegistryBackupSidecar -File $F).Problem | Should -Be 'MetadataMissing'
            $json = [System.IO.Path]::ChangeExtension($F, '.json')
            'kein json {' | Set-Content -LiteralPath $json
            (Read-RegistryBackupSidecar -File $F).Problem | Should -Be 'MetadataInvalid'
            Write-RegistryBackupSidecar -File $F -ActionId ([guid]::NewGuid().ToString()) -Name 'Jan' -NativeKey 'K' -Scope 'User' -Reasons @()
            (Read-RegistryBackupSidecar -File $F).Problem | Should -Be 'MetadataInvalid' -Because 'ActionId passt nicht zum Dateinamen'
        }
    }
}

Describe 'Sicherung mit dem echten reg.exe' {
    It 'erkennt eine echte reg-export-Datei als brauchbar' {
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation { @(@{ Path = 'TestRegistry:\RealExport'; Scope = 'User'; Architecture = $null }) }
        $key = New-Item -Path 'TestRegistry:\RealExport\janold' -Force
        New-ItemProperty -Path $key.PSPath -Name DisplayName -Value 'Jan 0.5.16' | Out-Null
        $file = Join-Path $TestDrive 'real.reg'
        InModuleScope SoftwareInventory -Parameters @{ K = $key.Name; F = $file } {
            Invoke-RegExport -NativeKey $K -File $F | Should -Be 0
            Test-RegistryBackup -File $F -NativeKey $K | Should -BeNullOrEmpty
            Test-RegistryBackup -File $F -NativeKey 'HKEY_CURRENT_USER\Software\Anderer' | Should -Be 'KeyMismatch'
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
