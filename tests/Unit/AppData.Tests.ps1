BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\SoftwareInventory\SoftwareInventory.psd1') -Force
}

Describe 'App-Ordner zentral (Get-AppDataRoot)' {
    BeforeEach {
        $script:Saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
    }
    AfterEach {
        $env:APPDATA = $script:Saved.APPDATA
        $env:LOCALAPPDATA = $script:Saved.LOCALAPPDATA
    }

    It 'setzt den App-Ordner aus der Umgebungsvariablen zusammen' {
        $env:APPDATA = Join-Path $TestDrive 'Roaming'
        $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
        InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Roaming } | Should -Be (Join-Path $TestDrive 'Roaming\SoftwareInventory')
        InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local } | Should -Be (Join-Path $TestDrive 'Local\SoftwareInventory')
        InModuleScope SoftwareInventory { Get-SettingsPath } | Should -Be (Join-Path $TestDrive 'Roaming\SoftwareInventory\settings.json')
        InModuleScope SoftwareInventory { Get-CpeMappingPath } | Should -Be (Join-Path $TestDrive 'Roaming\SoftwareInventory\cpe-map.json')
        InModuleScope SoftwareInventory { Get-CacheDirectory } | Should -Be (Join-Path $TestDrive 'Local\SoftwareInventory\cache')
        InModuleScope SoftwareInventory { Get-DefaultSnapshotDirectory } | Should -Be (Join-Path $TestDrive 'Local\SoftwareInventory\scans')
    }

    It 'bricht bei ungültigem Wert mit AppDataRootInvalid ab: <Case>' -ForEach @(
        @{ Case = 'leer'; Value = '' }
        @{ Case = 'nur Leerzeichen'; Value = '   ' }
        @{ Case = 'relativ'; Value = 'AppData\Roaming' }
        @{ Case = 'Laufwerk ohne Wurzel'; Value = 'C:AppData' }
        @{ Case = 'ohne Laufwerk'; Value = '\AppData' }
        @{ Case = 'Gerätepfad'; Value = '\\?\C:\AppData' }
        @{ Case = 'Gerätepfad mit Punkt'; Value = '\\.\C:\AppData' }
    ) {
        $env:APPDATA = $Value
        $caught = $null
        try { InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Roaming } } catch { $caught = $_.Exception }
        $caught | Should -Not -BeNullOrEmpty
        $caught.Data['Code'] | Should -Be 'AppDataRootInvalid'
        $caught.Data['Args'][0] | Should -Be 'APPDATA'
    }

    It 'erlaubt UNC im Betrieb, lehnt es aber für das Entfernen ab' {
        $env:LOCALAPPDATA = '\\server\freigabe\profil\AppData\Local'
        InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local } | Should -Be '\\server\freigabe\profil\AppData\Local\SoftwareInventory'
        $caught = $null
        try { InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local -ForRemoval } } catch { $caught = $_.Exception }
        $caught.Data['Code'] | Should -Be 'AppDataRootInvalid'
    }

    It 'lehnt ein Netzlaufwerk für das Entfernen ab' {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
        Mock -ModuleName SoftwareInventory Get-AppDataDriveType { 'Network' }
        $caught = $null
        try { InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local -ForRemoval } } catch { $caught = $_.Exception }
        $caught.Data['Code'] | Should -Be 'AppDataRootInvalid'
    }

    It 'lehnt für das Entfernen ein fehlendes Laufwerk ab, im Betrieb bleibt der Pfad erlaubt' {
        $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpperInvariant() })
        $free = [char[]] ([int][char] 'D'..[int][char] 'Z') | Where-Object { [string] $_ -notin $used } | Select-Object -Last 1
        if (-not $free) { Set-ItResult -Skipped -Because 'kein freier Laufwerksbuchstabe'; return }
        $env:LOCALAPPDATA = "${free}:\AppData\Local"
        InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local } | Should -Be "${free}:\AppData\Local\SoftwareInventory"
        $caught = $null
        try { InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local -ForRemoval } } catch { $caught = $_.Exception }
        $caught.Data['Code'] | Should -Be 'AppDataRootInvalid'
    }

    It 'lehnt für das Entfernen ab, wenn sich die Laufwerksart nicht bestimmen lässt' {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'Local'
        Mock -ModuleName SoftwareInventory Get-AppDataDriveType { throw [System.IO.IOException]::new('Laufwerk fehlt') }
        $caught = $null
        try { InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local -ForRemoval } } catch { $caught = $_.Exception }
        $caught.Data['Code'] | Should -Be 'AppDataRootInvalid'
    }

    It 'löst „..“ für das Entfernen auf' {
        $env:LOCALAPPDATA = Join-Path $TestDrive 'Local\x\..'
        InModuleScope SoftwareInventory { Get-AppDataRoot -Scope Local -ForRemoval } | Should -Be (Join-Path $TestDrive 'Local\SoftwareInventory')
    }

    It 'Wächter: Nur AppData.ps1 setzt App-Ordner aus Umgebung oder Program Files zusammen' {
        $root = Join-Path $PSScriptRoot '..\..\src\SoftwareInventory'
        $hits = foreach ($file in Get-ChildItem -LiteralPath $root -Recurse -File -Include '*.ps1', '*.psm1') {
            if ($file.Name -eq 'AppData.ps1') { continue }
            $number = 0
            foreach ($line in [System.IO.File]::ReadAllLines($file.FullName)) {
                $number++
                $fromEnvironment = $line -match '(?i)\$env:(LOCAL)?APPDATA|GetEnvironmentVariable\([''"](LOCAL)?APPDATA' -and $line -match 'SoftwareInventory'
                $fromProgramFiles = $line -match '(?i)ProgramFiles' -and $line -match 'Softwareverwaltung'
                if ($fromEnvironment -or $fromProgramFiles) { "$($file.Name):$number" }
            }
        }
        $hits | Should -BeNullOrEmpty
    }
}

Describe 'App-Daten entfernen (8c-1)' {
    BeforeAll {
        function New-TestFile([string] $Path, [int] $Size = 10) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
            [System.IO.File]::WriteAllBytes($Path, [byte[]]::new($Size))
        }
    }

    BeforeEach {
        $script:Saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
        $base = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $env:APPDATA = Join-Path $base 'Roaming'
        $env:LOCALAPPDATA = Join-Path $base 'Local'
        $script:Roaming = Join-Path $env:APPDATA 'SoftwareInventory'
        $script:Local = Join-Path $env:LOCALAPPDATA 'SoftwareInventory'
        $script:Temp = Join-Path $base 'Temp'
        $script:Machine = Join-Path $base 'ProgramFiles\Softwareverwaltung'
        $script:Outside = Join-Path $base 'Outside'
        New-Item -ItemType Directory -Path $script:Temp, $script:Outside -Force | Out-Null
        Mock -ModuleName SoftwareInventory Get-AppTempDirectory { $script:Temp }
        # Nie den echten Admin-Ordner lesen.
        Mock -ModuleName SoftwareInventory Get-AppMachineDirectory { $script:Machine }
        # Nie eine echte UAC-Abfrage: Der erhöhte Start wird immer ersetzt; ohne eigenen Mock gilt „abgelehnt“.
        Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { throw [System.ComponentModel.Win32Exception]::new(1223) }
        # Nie echte Schlüssel lesen oder löschen.
        $script:Secrets = @{}
        Mock -ModuleName SoftwareInventory Read-StoredSecret { $script:Secrets[$Service] }
        Mock -ModuleName SoftwareInventory Remove-StoredSecret {
            if ($script:Secrets.ContainsKey($Service)) { $script:Secrets.Remove($Service); 'Removed' } else { 'NotPresent' }
        }
    }
    AfterEach {
        InModuleScope SoftwareInventory { $script:AppDataRemoved = $false }
        $env:APPDATA = $script:Saved.APPDATA
        $env:LOCALAPPDATA = $script:Saved.LOCALAPPDATA
    }

    It 'zählt im Plan Orte, Sicherungen, CPE-Zuordnungen, Schlüssel und Temp-Reste' {
        New-TestFile (Join-Path $script:Roaming 'settings.json') 100
        Set-Content -LiteralPath (Join-Path $script:Roaming 'cpe-map.json') -Value '[{"Key":"a","Cpe":"cpe:2.3:a:x:y"},{"Key":"b","Cpe":"cpe:2.3:a:x:z"}]'
        New-TestFile (Join-Path $script:Local 'cache\NVD\a.json') 50
        $id = [guid]::NewGuid().ToString()
        New-TestFile (Join-Path $script:Local "logs\registry-backup\${id}_Jan.reg") 20
        $machineId = [guid]::NewGuid().ToString()
        New-TestFile (Join-Path $script:Machine "RegistryBackup\$machineId.reg") 30
        New-TestFile (Join-Path $script:Temp "SoftwareInventory-$([guid]::NewGuid().ToString('N')).log") 5
        New-TestFile (Join-Path $script:Temp 'fremd.log') 5
        $script:Secrets['NVD'] = 'x'

        $plan = Get-AppDataRemovalPlan
        ($plan.Locations | Where-Object Kind -EQ 'Roaming').State | Should -Be 'Present'
        ($plan.Locations | Where-Object Kind -EQ 'Roaming').FileCount | Should -Be 2
        ($plan.Locations | Where-Object Kind -EQ 'Local').FileCount | Should -Be 2
        ($plan.Locations | Where-Object Kind -EQ 'Local').Size | Should -Be 70
        ($plan.Locations | Where-Object Kind -EQ 'Temp').FileCount | Should -Be 1
        ($plan.Locations | Where-Object Kind -EQ 'Machine').State | Should -Be 'Present'
        $plan.UserBackupCount | Should -Be 1
        $plan.MachineBackupCount | Should -Be 1
        $plan.CpeMappingCount | Should -Be 2
        $plan.StoredCredentials | Should -Be @('NVD')
        $plan.TempFiles.Count | Should -Be 1
    }

    It '-WhatIf ändert nichts und liefert den Plan' {
        New-TestFile (Join-Path $script:Roaming 'settings.json')
        $script:Secrets['GitHub'] = 'x'
        $result = Remove-AppData -WhatIf
        $result.PSObject.TypeNames[0] | Should -Be 'SoftwareInventory.AppDataRemovalPlan'
        Test-Path -LiteralPath (Join-Path $script:Roaming 'settings.json') | Should -BeTrue
        Should -Invoke -ModuleName SoftwareInventory Remove-StoredSecret -Times 0
    }

    It 'entfernt beide App-Ordner, Schlüssel und Temp-Reste, lässt Fremdes stehen' {
        New-TestFile (Join-Path $script:Roaming 'settings.json')
        New-TestFile (Join-Path $script:Local 'logs\actions\2026-11-21.jsonl')
        $ownLog = Join-Path $script:Temp "SoftwareInventory-$([guid]::NewGuid().ToString('N'))-2.log"
        $ownReg = Join-Path $script:Temp "SoftwareInventory-restore-$([guid]::NewGuid()).reg"
        New-TestFile $ownLog; New-TestFile $ownReg
        $foreign = @(
            (Join-Path $script:Temp 'SoftwareInventory-x.log')
            (Join-Path $script:Temp "SoftwareInventory-$([guid]::NewGuid().ToString('N')).log.bak")
            (Join-Path $script:Temp "SoftwareInventory-restore-$([guid]::NewGuid().ToString('N')).reg")
            (Join-Path $script:Temp "Unterordner\SoftwareInventory-$([guid]::NewGuid().ToString('N')).log")
            (Join-Path $env:LOCALAPPDATA 'AndereApp\daten.txt')
        )
        foreach ($path in $foreign) { New-TestFile $path }
        $script:Secrets['NVD'] = 'x'; $script:Secrets['Advisor'] = 'y'

        $result = Remove-AppData -Confirm:$false
        $result.Result | Should -Be 'Removed'
        $result.Message.Code | Should -Be 'AppDataRemovalDone'
        Test-Path -LiteralPath $script:Roaming | Should -BeFalse
        Test-Path -LiteralPath $script:Local | Should -BeFalse
        Test-Path -LiteralPath $ownLog | Should -BeFalse
        Test-Path -LiteralPath $ownReg | Should -BeFalse
        foreach ($path in $foreign) { Test-Path -LiteralPath $path | Should -BeTrue }
        $script:Secrets.Count | Should -Be 0
        ($result.Items | Where-Object Kind -EQ 'Credentials').Message.Code | Should -Be 'AppDataCredentialRemoved'
        ($result.Items | Where-Object Kind -EQ 'Temp').RemovedCount | Should -Be 2
        $result.Items.Kind | Should -Be @('Machine', 'Credentials', 'Temp', 'Local', 'Roaming')
        ($result.Items | Where-Object Kind -EQ 'Machine').Result | Should -Be 'NotPresent'
        Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 0
    }

    It 'meldet NotPresent, wenn nichts da ist' {
        $result = Remove-AppData -Confirm:$false
        $result.Result | Should -Be 'NotPresent'
        $result.Message.Code | Should -Be 'AppDataRemovalNothing'
    }

    It 'entfernt eine Junction im App-Ordner als Link, ihr Ziel bleibt' {
        New-TestFile (Join-Path $script:Outside 'wichtig.txt')
        New-Item -ItemType Directory -Path $script:Local -Force | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $script:Local 'cache') -Target $script:Outside | Out-Null
        $plan = Get-AppDataRemovalPlan
        ($plan.Locations | Where-Object Kind -EQ 'Local').LinkCount | Should -Be 1
        ($plan.Locations | Where-Object Kind -EQ 'Local').FileCount | Should -Be 0

        $result = Remove-AppData -Confirm:$false
        $result.Result | Should -Be 'Removed'
        Test-Path -LiteralPath $script:Local | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:Outside 'wichtig.txt') | Should -BeTrue
    }

    It 'entfernt einen Datei-Symlink als Link, sein Ziel bleibt (sofern Symlinks erlaubt sind)' {
        New-TestFile (Join-Path $script:Outside 'ziel.txt')
        New-Item -ItemType Directory -Path $script:Local -Force | Out-Null
        try { New-Item -ItemType SymbolicLink -Path (Join-Path $script:Local 'link.txt') -Target (Join-Path $script:Outside 'ziel.txt') -ErrorAction Stop | Out-Null }
        catch { Set-ItResult -Skipped -Because 'ohne Recht für symbolische Links (Entwicklermodus oder Administrator)'; return }
        (Remove-AppData -Confirm:$false).Result | Should -Be 'Removed'
        Test-Path -LiteralPath (Join-Path $script:Outside 'ziel.txt') | Should -BeTrue
    }

    It 'lässt einen App-Ordner stehen, der selbst eine Junction ist (AppDataRootIsLink)' {
        New-TestFile (Join-Path $script:Outside 'wichtig.txt')
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null
        New-Item -ItemType Junction -Path $script:Local -Target $script:Outside | Out-Null
        (Get-AppDataRemovalPlan).Locations | Where-Object Kind -EQ 'Local' | ForEach-Object State | Should -Be 'RootIsLink'

        $result = Remove-AppData -Confirm:$false
        $result.Result | Should -Be 'PartlyRemoved'
        $local = $result.Items | Where-Object Kind -EQ 'Local'
        $local.Result | Should -Be 'Skipped'
        $local.Problems.Code | Should -Be 'AppDataRootIsLink'
        Test-Path -LiteralPath (Join-Path $script:Outside 'wichtig.txt') | Should -BeTrue
        Test-Path -LiteralPath $script:Local | Should -BeTrue
    }

    It 'entfernt den Rest, wenn eine Datei gesperrt ist (PartlyRemoved)' {
        $locked = Join-Path $script:Local 'logs\offen.log'
        New-TestFile $locked
        New-TestFile (Join-Path $script:Local 'cache\a.json')
        $stream = [System.IO.File]::Open($locked, 'Open', 'Read', 'None')
        try { $result = Remove-AppData -Confirm:$false }
        finally { $stream.Dispose() }
        $local = $result.Items | Where-Object Kind -EQ 'Local'
        $local.Result | Should -Be 'PartlyRemoved'
        $local.FirstFailedPath | Should -Be $locked
        $local.Message.Code | Should -Be 'AppDataPartlyRemoved'
        Test-Path -LiteralPath (Join-Path $script:Local 'cache\a.json') | Should -BeFalse
        Test-Path -LiteralPath $locked | Should -BeTrue
    }

    It 'meldet einen unlesbaren Unterordner und entfernt den Rest (AppDataUnreadable)' {
        $blocked = Join-Path $script:Local 'cache\gesperrt'
        New-TestFile (Join-Path $blocked 'a.json')
        New-TestFile (Join-Path $script:Local 'logs\b.log')
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new($sid, 'ListDirectory', 'Deny')
        $acl = Get-Acl -LiteralPath $blocked
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $blocked -AclObject $acl
        try {
            $plan = Get-AppDataRemovalPlan
            ($plan.Locations | Where-Object Kind -EQ 'Local').Problems.Code | Should -Contain 'AppDataUnreadable'
            $local = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Local'
            $local.Result | Should -Be 'PartlyRemoved'
            $local.Problems.Code | Should -Contain 'AppDataUnreadable'
            Test-Path -LiteralPath (Join-Path $script:Local 'logs\b.log') | Should -BeFalse
            Test-Path -LiteralPath $blocked | Should -BeTrue
        }
        finally {
            # Deny wieder entfernen, sonst lässt sich TestDrive nicht aufräumen.
            $acl = Get-Acl -LiteralPath $blocked
            [void] $acl.RemoveAccessRule($rule)
            Set-Acl -LiteralPath $blocked -AclObject $acl
        }
    }

    It 'entfernt auch schreibgeschützte Dateien' {
        $file = Join-Path $script:Roaming 'settings.json'
        New-TestFile $file
        (Get-Item -LiteralPath $file).Attributes = 'ReadOnly'
        (Remove-AppData -Confirm:$false).Result | Should -Be 'Removed'
        Test-Path -LiteralPath $script:Roaming | Should -BeFalse
    }

    It 'löscht nichts in einem Ordner auf UNC und meldet AppDataRootInvalid' {
        # localhost mit fehlender Freigabe: Der Plan liest cpe-map.json, das scheitert hier sofort statt nach einer Netzsuche.
        $env:APPDATA = '\\localhost\SoftwareInventoryTestFehlt$\AppData\Roaming'
        New-TestFile (Join-Path $script:Local 'cache\a.json')
        $result = Remove-AppData -Confirm:$false
        $roaming = $result.Items | Where-Object Kind -EQ 'Roaming'
        $roaming.Result | Should -Be 'Skipped'
        $roaming.Problems.Code | Should -Be 'AppDataRootInvalid'
        ($result.Items | Where-Object Kind -EQ 'Local').Result | Should -Be 'Removed'
        $result.Result | Should -Be 'PartlyRemoved'
        ((Get-AppDataRemovalPlan).Locations | Where-Object Kind -EQ 'Roaming').State | Should -Be 'Invalid'
    }

    It 'meldet einen Schlüssel, der sich nicht löschen lässt' {
        $script:Secrets['NVD'] = 'x'
        Mock -ModuleName SoftwareInventory Remove-StoredSecret { if ($Service -eq 'NVD') { 'Failed' } else { 'NotPresent' } }
        $credentials = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Credentials'
        $credentials.Result | Should -Be 'PartlyRemoved'
        $credentials.Problems.Code | Should -Be 'AppDataCredentialFailed'
    }

    It 'löscht jeden Dienst direkt, auch wenn der Eintrag nicht lesbar ist' {
        # Read-StoredSecret liefert hier nichts (leerer oder unlesbarer Eintrag), gelöscht wird trotzdem.
        Mock -ModuleName SoftwareInventory Remove-StoredSecret { if ($Service -eq 'GitHub') { 'Removed' } else { 'NotPresent' } }
        $credentials = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Credentials'
        $credentials.Result | Should -Be 'Removed'
        Should -Invoke -ModuleName SoftwareInventory Remove-StoredSecret -Times 4 -Exactly
    }

    It 'lässt einen App-Ordner stehen, der eine Datei ist (AppDataRootNotFolder)' {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
        [System.IO.File]::WriteAllText($script:Roaming, 'keine Ordner')
        $roaming = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Roaming'
        $roaming.Result | Should -Be 'Skipped'
        $roaming.Problems.Code | Should -Be 'AppDataRootNotFolder'
        Test-Path -LiteralPath $script:Roaming -PathType Leaf | Should -BeTrue
    }

    It 'kommt damit zurecht, dass APPDATA und LOCALAPPDATA derselbe Ordner sind' {
        $env:APPDATA = $env:LOCALAPPDATA
        New-TestFile (Join-Path $script:Local 'settings.json')
        $result = Remove-AppData -Confirm:$false
        ($result.Items | Where-Object Kind -EQ 'Local').Result | Should -Be 'Removed'
        ($result.Items | Where-Object Kind -EQ 'Roaming').Result | Should -Be 'NotPresent'
        $result.Result | Should -Be 'Removed'
    }

    It 'lehnt danach Aktionen und gespeicherte Daten mit AppDataAlreadyRemoved ab' {
        [void] (Remove-AppData -Confirm:$false)
        $codes = foreach ($call in @(
                { InModuleScope SoftwareInventory { Write-ActionLogEntry -Phase Started -Data @{ ActionId = 'x'; Action = 'Test' } } }
                { Set-InventorySetting -LogRetentionDays 10 -Confirm:$false }
                { @([pscustomobject] @{ Name = 'x' }) | Save-InventorySnapshot -Confirm:$false }
                { InModuleScope SoftwareInventory { Write-CpeMapping -Map @{} } }
                { InModuleScope SoftwareInventory { Write-RegistryBackupSidecar -File 'x.reg' -ActionId 'x' -Name 'x' -NativeKey 'x' -Scope 'User' -Reasons @() } }
            )) {
            try { & $call; 'kein Abbruch' } catch { [string] $_.Exception.Data['Code'] + '|' + $_.Exception.GetType().Name + '|' + $_.Exception.Message }
        }
        ($codes | ForEach-Object { ($_ -split '\|')[0] }) -join ',' | Should -Be ((@('AppDataAlreadyRemoved') * 5) -join ',') -Because ($codes -join ' // ')
        Test-Path -LiteralPath $script:Local | Should -BeFalse
        Test-Path -LiteralPath $script:Roaming | Should -BeFalse
    }

    Context 'Admin-Ordner (8c-2)' {
        BeforeEach {
            $script:HelperExe = Join-Path $script:Machine 'Helper\0.1.0\SoftwareInventory.Helper.exe'
            $script:MachineReg = Join-Path $script:Machine "RegistryBackup\$([guid]::NewGuid()).reg"
            New-TestFile $script:HelperExe; New-TestFile $script:MachineReg
            New-TestFile (Join-Path $script:Roaming 'settings.json')
            # Erfolgreicher erhöhter Lauf: die echte cmd-Zeile ohne Erhöhung ausführen (TestDrive ist beschreibbar).
            $script:RunCmd = {
                param($Tool, $Arguments)
                $info = [System.Diagnostics.ProcessStartInfo]::new((Join-Path ([Environment]::GetFolderPath('System')) $Tool), $Arguments)
                $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.RedirectStandardError = $true
                $process = [System.Diagnostics.Process]::Start($info)
                [void] $process.StandardError.ReadToEnd()
                $process.WaitForExit()
                $process.ExitCode
            }
        }

        It 'entfernt Helper und RegistryBackup in einem erhöhten Lauf, zuerst vor allem anderen' {
            $script:Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { $script:Order.Add('Machine'); & $script:RunCmd $Tool $Arguments }
            Mock -ModuleName SoftwareInventory Remove-StoredSecret { $script:Order.Add('Credentials'); 'NotPresent' }
            $plan = Get-AppDataRemovalPlan
            $plan.RequiresElevation | Should -BeTrue
            $plan.HelperCopyPresent | Should -BeTrue
            $plan.MachineBackupCount | Should -Be 1

            $result = Remove-AppData -Confirm:$false
            $result.Result | Should -Be 'Removed'
            ($result.Items | Where-Object Kind -EQ 'Machine').Result | Should -Be 'Removed'
            Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 1 -Exactly -ParameterFilter { $Tool -eq 'cmd.exe' }
            $script:Order[0] | Should -Be 'Machine'
            Test-Path -LiteralPath $script:Machine | Should -BeFalse
        }

        It 'lässt Softwareverwaltung stehen, wenn dort noch Fremdes liegt (spätere Installation)' {
            $foreign = Join-Path $script:Machine 'Softwareverwaltung.exe'
            New-TestFile $foreign
            Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { & $script:RunCmd $Tool $Arguments }
            ($r = Remove-AppData -Confirm:$false).Result | Should -Be 'Removed'
            Test-Path -LiteralPath $foreign | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Machine 'Helper') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $script:Machine 'RegistryBackup') | Should -BeFalse
        }

        It 'rd /s folgt einer Junction in Helper nicht (echte cmd-Zeile ohne Erhöhung)' {
            New-TestFile (Join-Path $script:Outside 'wichtig.txt')
            New-Item -ItemType Junction -Path (Join-Path $script:Machine 'Helper\link') -Target $script:Outside | Out-Null
            Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { & $script:RunCmd $Tool $Arguments }
            (Remove-AppData -Confirm:$false).Result | Should -Be 'Removed'
            Test-Path -LiteralPath (Join-Path $script:Outside 'wichtig.txt') | Should -BeTrue
            Test-Path -LiteralPath (Join-Path $script:Machine 'Helper') | Should -BeFalse
        }

        It 'entfernt bei abgelehnter UAC-Abfrage alles andere (AppDataMachineDenied)' {
            $result = Remove-AppData -Confirm:$false
            $machine = $result.Items | Where-Object Kind -EQ 'Machine'
            $machine.Result | Should -Be 'Skipped'
            $machine.Problems.Code | Should -Be 'AppDataMachineDenied'
            $result.Result | Should -Be 'PartlyRemoved'
            Test-Path -LiteralPath $script:HelperExe | Should -BeTrue
            Test-Path -LiteralPath $script:Roaming | Should -BeFalse
        }

        It 'meldet ein Zeitlimit und noch vorhandene Ordner' {
            Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { $null }
            $machine = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Machine'
            $machine.Result | Should -Be 'PartlyRemoved'
            $machine.Problems.Code | Should -Contain 'AppDataMachineTimeout'
            $machine.FailedCount | Should -Be 2
        }

        It 'meldet einen Teilerfolg, wenn ein Unterordner bleibt' {
            Mock -ModuleName SoftwareInventory Invoke-ElevatedSystemTool { Remove-Item -LiteralPath (Join-Path $script:Machine 'RegistryBackup') -Recurse -Force; 0 }
            $machine = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Machine'
            $machine.Result | Should -Be 'PartlyRemoved'
            $machine.RemovedCount | Should -Be 1
            $machine.FirstFailedPath | Should -Be (Join-Path $script:Machine 'Helper')
        }

        It 'fragt ohne Unterordner nicht nach Administratorrechten' {
            Remove-Item -LiteralPath (Join-Path $script:Machine 'Helper'), (Join-Path $script:Machine 'RegistryBackup') -Recurse -Force
            (Get-AppDataRemovalPlan).RequiresElevation | Should -BeFalse
            ((Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Machine').Result | Should -Be 'NotPresent'
            Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 0
        }

        It 'fragt mit -SkipMachine nie nach Administratorrechten' {
            $result = Remove-AppData -SkipMachine -Confirm:$false
            $result.Items.Kind | Should -Not -Contain 'Machine'
            $result.Result | Should -Be 'Removed'
            Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 0
            Test-Path -LiteralPath $script:HelperExe | Should -BeTrue
        }

        It 'fragt nicht, wenn <Which> eine Junction ist (AppDataRootIsLink)' -ForEach @(
            @{ Which = 'Softwareverwaltung' }
            @{ Which = 'Helper' }
            @{ Which = 'RegistryBackup' }
        ) {
            New-TestFile (Join-Path $script:Outside 'wichtig.txt')
            $path = if ($Which -eq 'Softwareverwaltung') { $script:Machine } else { Join-Path $script:Machine $Which }
            Remove-Item -LiteralPath $path -Recurse -Force
            New-Item -ItemType Junction -Path $path -Target $script:Outside | Out-Null
            $machine = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Machine'
            $machine.Result | Should -Be 'Skipped'
            $machine.Problems.Code | Should -Contain 'AppDataRootIsLink'
            Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 0
            Test-Path -LiteralPath (Join-Path $script:Outside 'wichtig.txt') | Should -BeTrue
        }

        It 'fragt nicht bei Zeichen, die cmd deutet (<Char>), und meldet AppDataRootInvalid' -ForEach @(
            @{ Char = '%' }, @{ Char = '^' }, @{ Char = '&' }, @{ Char = '!' }
        ) {
            $script:Machine = Join-Path $TestDrive "Pro${Char}gram\Softwareverwaltung"
            New-TestFile (Join-Path $script:Machine 'Helper\x.exe')
            (Get-AppDataRemovalPlan).Locations | Where-Object Kind -EQ 'Machine' | ForEach-Object { $_.Problems.Code } | Should -Contain 'AppDataRootInvalid'
            $machine = (Remove-AppData -Confirm:$false).Items | Where-Object Kind -EQ 'Machine'
            $machine.Result | Should -Be 'Skipped'
            $machine.Problems.Code | Should -Be 'AppDataRootInvalid'
            Should -Invoke -ModuleName SoftwareInventory Invoke-ElevatedSystemTool -Times 0
            Test-Path -LiteralPath (Join-Path $script:Machine 'Helper\x.exe') | Should -BeTrue
        }

        It 'baut keine cmd-Zeile mit <Char> im Pfad' -ForEach @(
            @{ Char = '"' }, @{ Char = '%' }, @{ Char = '^' }, @{ Char = '&' }, @{ Char = '|' }, @{ Char = '<' }, @{ Char = '>' }, @{ Char = '!' }
        ) {
            InModuleScope SoftwareInventory -Parameters @{ Root = "C:\Pro${Char}gram\Softwareverwaltung" } { param($Root) Get-AppMachineRemovalCommand -Root $Root } | Should -BeNullOrEmpty
        }

        It 'baut die cmd-Zeile mit /d, /v:off und dem Ordner zuletzt ohne /s' {
            $command = InModuleScope SoftwareInventory { Get-AppMachineRemovalCommand -Root 'C:\Program Files\Softwareverwaltung' }
            $command | Should -Be '/d /v:off /c rd /s /q "C:\Program Files\Softwareverwaltung\Helper" & rd /s /q "C:\Program Files\Softwareverwaltung\RegistryBackup" & rd "C:\Program Files\Softwareverwaltung"'
        }
    }

    It 'schreibt danach nichts mehr: Fehlerprotokoll, Hinweise, Aktionsprotokoll, Zwischenspeicher, Bereinigung' {
        New-TestFile (Join-Path $script:Local 'logs\a.log')
        [void] (Remove-AppData -Confirm:$false)
        InModuleScope SoftwareInventory {
            Write-ModuleErrorLog -Origin 'Test' -Message 'nach dem Entfernen'
            Write-DataNote -Code 'CommitAsVersion' -Source 'Test' -CveId 'CVE-2026-0001' -Value 'x'
            Write-ServiceCache -Path (Join-Path (Get-CacheDirectory) 'NVD\x.json') -Content '{}'
            Write-CheckIndexFile -Path (Join-Path (Get-CacheDirectory) 'index\x.json') -Text '{}'
            Write-CirclStore -Path (Join-Path (Get-CacheDirectory) 'CIRCL\x.json') -Store @{ FullAt = [datetime]::UtcNow; FetchedAt = [datetime]::UtcNow; Records = @{} }
            Write-EpssStore -Path (Join-Path (Get-CacheDirectory) 'EPSS\scores.json') -Store @{}
            Invoke-AppDataCleanup | Should -Be 0
        }
        Test-Path -LiteralPath $script:Local | Should -BeFalse
    }

    It 'ist kein Werkzeug des KI-Beraters' {
        (Get-AdvisorTool).Name | Should -Not -Match '(?i)app_?data|remove_app'
    }
}

Describe 'Gespeicherte Schlüssel entfernen (echte Anmeldeinformationsverwaltung, eigener Präfix)' {
    BeforeEach {
        InModuleScope SoftwareInventory -Parameters @{ Prefix = "SoftwareInventory-Test-$([guid]::NewGuid())" } {
            param($Prefix)
            $script:SavedCredentialPrefix = $script:CredentialPrefix
            $script:CredentialPrefix = $Prefix
        }
    }
    AfterEach {
        InModuleScope SoftwareInventory {
            foreach ($service in $script:SecretVariable.Keys) { [void] [SoftwareInventory.CredentialStore]::Delete((Get-CredentialTarget $service)) }
            $script:CredentialPrefix = $script:SavedCredentialPrefix
        }
    }

    It 'Remove-StoredSecret löscht den Eintrag und ist ohne Eintrag ebenfalls erfolgreich' {
        Set-ServiceCredential -Service CIRCL -Secret (ConvertTo-SecureString 'circl-test' -AsPlainText -Force) | Out-Null
        InModuleScope SoftwareInventory { Get-AppStoredCredential } | Should -Be @('CIRCL')
        InModuleScope SoftwareInventory { Remove-StoredSecret -Service CIRCL } | Should -Be 'Removed'
        InModuleScope SoftwareInventory { Get-AppStoredCredential } | Should -BeNullOrEmpty
        InModuleScope SoftwareInventory { Remove-StoredSecret -Service CIRCL } | Should -Be 'NotPresent'
    }
}
