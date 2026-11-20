BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\..\src\SoftwareInventory\SoftwareInventory.psd1') -Force
}

Describe 'Sicherungen anzeigen, löschen und zurückspielen (8b-3)' {
    BeforeAll {
        # Eine echte reg-export-Sicherung samt Begleitdatei anlegen; der Schlüssel wird danach entfernt („entfernter Eintrag“).
        function New-TestBackup {
            param([string] $Name = 'Jan 0.5.16', [string] $Key = 'janold', [string] $Root = $script:UserRoot, [switch] $NoSidecar, $Reasons = @([pscustomobject] @{ Code = 'OrphanedEntry'; Args = @() }))
            $path = "$Root\$Key"
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name DisplayName -Value $Name | Out-Null
            $native = (Get-Item -LiteralPath $path).Name
            $id = [guid]::NewGuid().ToString()
            $dir = Join-Path $script:AppDir 'logs\registry-backup'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            $file = Join-Path $dir "${id}_$Key.reg"
            $exit = InModuleScope SoftwareInventory -Parameters @{ K = $native; F = $file } { Invoke-RegExport -NativeKey $K -File $F }
            $exit | Should -Be 0
            if (-not $NoSidecar) {
                InModuleScope SoftwareInventory -Parameters @{ F = $file; I = $id; N = $Name; K = $native; R = $Reasons } {
                    Write-RegistryBackupSidecar -File $F -ActionId $I -Name $N -NativeKey $K -Scope 'User' -Reasons $R
                }
            }
            Remove-Item -LiteralPath $path -Recurse -Force
            [pscustomobject] @{ Id = $id; File = $file; Native = $native; Path = $path; Sidecar = [System.IO.Path]::ChangeExtension($file, '.json') }
        }
        function Set-RegFileText([string] $File, [string] $Text) {
            [System.IO.File]::WriteAllText($File, $Text, [System.Text.UnicodeEncoding]::new($false, $true))
        }
    }

    BeforeEach {
        $script:AppDir = Join-Path $TestDrive "app-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $script:AppDir }
        # Nie den echten Admin-Ordner unter Program Files lesen.
        $script:MachineDir = Join-Path $script:AppDir 'ProgramFiles\Softwareverwaltung\RegistryBackup'
        Mock -ModuleName SoftwareInventory Get-RegistryBackupMachineDirectory { $script:MachineDir }
        $script:UserRoot = 'TestRegistry:\BackupUser'
        $script:MachineRoot = 'TestRegistry:\BackupMachine'
        Remove-Item -LiteralPath $script:UserRoot, $script:MachineRoot -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $script:UserRoot, $script:MachineRoot -Force | Out-Null
        Mock -ModuleName SoftwareInventory Get-DefaultUninstallLocation {
            @(@{ Path = $script:MachineRoot; Scope = 'Machine'; Architecture = 'X64' }, @{ Path = $script:UserRoot; Scope = 'User'; Architecture = $null })
        }
    }

    Context 'Get-RegistryBackup' {
        It 'liefert nichts, wenn es keine Sicherungen gibt' {
            @(Get-RegistryBackup) | Should -BeNullOrEmpty
        }

        It 'zeigt Name, Zeitpunkt, Schlüssel und Gründe als Codes; neueste zuerst' {
            $old = New-TestBackup -Name 'Alt'
            Start-Sleep -Milliseconds 1100
            $new = New-TestBackup -Name 'Neu' -Key 'neu' -Reasons @(
                [pscustomobject] @{ Code = 'OrphanedEntry'; Args = @() }
                [pscustomobject] @{ Code = 'NewerInstallNextTo'; Args = @('Jan', '0.8.8') })
            $list = @(Get-RegistryBackup)
            $list.Count | Should -Be 2
            $list[0].Name | Should -Be 'Neu'
            $list[0].Id | Should -Be $new.Id
            $list[0].NativeKey | Should -Be $new.Native
            $list[0].CanRestore | Should -BeTrue
            $list[0].IsLegacy | Should -BeFalse
            @($list[0].Reasons.Code) | Should -Be @('OrphanedEntry', 'NewerInstallNextTo')
            $list[0].Reasons[1].Text | Should -Be 'Neuere Installation daneben: Jan 0.8.8' -Because 'Text kommt aus der psd1, nicht aus der Datei'
            $list[0].CreatedAt.Kind | Should -Be 'Utc'
            $list[1].Name | Should -Be 'Alt'
        }

        It 'kennzeichnet ältere Sicherungen ohne Begleitdatei und liest den Namen aus der .reg-Datei' {
            $b = New-TestBackup -Name 'Mein "Programm" \x' -NoSidecar
            $item = Get-RegistryBackup -Id $b.Id
            $item.IsLegacy | Should -BeTrue
            $item.CanRestore | Should -BeFalse
            $item.Problem | Should -Be 'MetadataMissing'
            $item.ProblemMessage.Code | Should -Be 'BackupMetadataMissing'
            $item.Name | Should -Be 'Mein "Programm" \x'
            $item.NativeKey | Should -Be $b.Native
        }

        It 'meldet eine Sicherung als nicht zurückspielbar, wenn die .reg-Datei die Prüfung nicht besteht' {
            $b = New-TestBackup
            Set-RegFileText $b.File ("Windows Registry Editor Version 5.00`r`n`r`n[$($b.Native)]`r`n`r`n[HKEY_CURRENT_USER\Software\Fremd]`r`n")
            $item = Get-RegistryBackup -Id $b.Id
            $item.CanRestore | Should -BeFalse
            $item.Problem | Should -Be 'KeyOutside'
        }

        It 'ignoriert Dateien ohne Kennung im Namen' {
            $dir = Join-Path $script:AppDir 'logs\registry-backup'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            'x' | Set-Content (Join-Path $dir 'irgendwas.reg')
            @(Get-RegistryBackup) | Should -BeNullOrEmpty
        }
    }

    Context 'Restore-RegistryBackup' {
        It 'plant mit -WhatIf, ohne etwas zu importieren' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            $plan = Restore-RegistryBackup $b.Id -WhatIf
            $plan.Result | Should -Be 'Planned'
            $plan.Action | Should -Be 'RestoreBackup'
            $plan.CommandLine | Should -Be "$($b.Id) $($b.Native)" -Because 'bestätigt wird Kennung und Schlüssel'
            $plan.Message.Code | Should -Be 'PlanRestoreBackup'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
            Test-Path $b.Path | Should -BeFalse
        }

        It 'spielt mit dem echten reg.exe zurück, behält die Sicherung, löscht die temporäre Datei und protokolliert' {
            $b = New-TestBackup
            $plan = Restore-RegistryBackup $b.Id -WhatIf
            $r = Restore-RegistryBackup $b.Id -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
            $r.Result | Should -Be 'Succeeded'
            $r.Message.Code | Should -Be 'RestoreBackupDone'
            (Get-ItemProperty -LiteralPath $b.Path).DisplayName | Should -Be 'Jan 0.5.16'
            Test-Path $b.File | Should -BeTrue
            Test-Path $b.Sidecar | Should -BeTrue
            @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Filter "SoftwareInventory-restore-$($r.ActionId).reg" -ErrorAction SilentlyContinue) | Should -BeNullOrEmpty
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            $log.Phase | Should -Be @('Started', 'Completed')
            $log[1].Action | Should -Be 'RestoreBackup'
            $log[1].Result | Should -Be 'Succeeded'
        }

        It 'spielt auch Unterschlüssel zurück' {
            $b = New-TestBackup
            New-Item -Path $b.Path -Force | Out-Null
            New-Item -Path "$($b.Path)\Sub" -Force | Out-Null
            New-ItemProperty -Path "$($b.Path)\Sub" -Name A -Value '1' | Out-Null
            InModuleScope SoftwareInventory -Parameters @{ K = $b.Native; F = $b.File } { Invoke-RegExport -NativeKey $K -File $F } | Should -Be 0
            Remove-Item -LiteralPath $b.Path -Recurse -Force
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            (Get-ItemProperty -LiteralPath "$($b.Path)\Sub").A | Should -Be '1'
        }

        It 'importiert genau den geprüften Inhalt, auch wenn die Sicherung währenddessen ausgetauscht wird' {
            $b = New-TestBackup
            $script:Original = [System.IO.File]::ReadAllBytes($b.File)
            $script:BackupFile = $b.File
            $script:Imported = $null; $script:ImportedFile = $null
            Mock -ModuleName SoftwareInventory Invoke-RegImport {
                $script:ImportedFile = $File
                $script:Imported = [System.IO.File]::ReadAllBytes($File)
                # Angreifer tauscht die Sicherung nach der Prüfung aus
                [System.IO.File]::WriteAllText($script:BackupFile, 'Windows Registry Editor Version 5.00', [System.Text.UnicodeEncoding]::new($false, $true))
                0
            }
            $null = Restore-RegistryBackup $b.Id -Confirm:$false
            $script:Imported | Should -Not -BeNullOrEmpty
            [System.Convert]::ToBase64String($script:Imported) | Should -Be ([System.Convert]::ToBase64String($script:Original))
            $script:ImportedFile | Should -Not -Be $b.File
            Test-Path -LiteralPath $script:ImportedFile | Should -BeFalse -Because 'die temporäre Datei wird danach gelöscht'
        }

        It 'lehnt ältere Sicherungen ohne Begleitdatei ab (BackupMetadataMissing)' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup -NoSidecar
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Unsupported'
            $r.Message.Code | Should -Be 'BackupMetadataMissing'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'lehnt eine kaputte Begleitdatei ab (BackupMetadataInvalid)' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            'kein json {' | Set-Content -LiteralPath $b.Sidecar
            (Restore-RegistryBackup $b.Id -Confirm:$false).Message.Code | Should -Be 'BackupMetadataInvalid'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'lehnt eine veränderte Sicherung ab (<Case>) und schreibt einen Protokolleintrag' -TestCases @(
            @{ Case = 'fremder Schlüssel'; Code = 'BackupKeyOutside'; Mutate = { param($t, $n) $t + "`r`n[HKEY_CURRENT_USER\Software\Fremd]`r`n" } }
            @{ Case = 'Löschzeile'; Code = 'BackupDeleteLine'; Mutate = { param($t, $n) $t + "`r`n[-HKEY_CURRENT_USER\Software\Fremd]`r`n" } }
            @{ Case = 'falscher Kopf'; Code = 'BackupBadHeader'; Mutate = { param($t, $n) $t -replace 'Windows Registry Editor Version 5.00', 'REGEDIT4' } }
            @{ Case = 'Präfix-Trick'; Code = 'BackupKeyOutside'; Mutate = { param($t, $n) $t + "`r`n[${n}X]`r`n" } }
        ) {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            $text = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($b.File), 2, ([System.IO.File]::ReadAllBytes($b.File)).Length - 2)
            Set-RegFileText $b.File (& $Mutate $text $b.Native)
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Unsupported'
            $r.Message.Code | Should -Be $Code
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
            Test-Path $b.Path | Should -BeFalse
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            $log[-1].Result | Should -Be 'Unsupported'
            $log[-1].Message.Code | Should -Be $Code
        }

        It 'bricht ab, wenn sich der Schlüssel in der Begleitdatei nach der Bestätigung ändert' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            $plan = Restore-RegistryBackup $b.Id -WhatIf
            $json = Get-Content -LiteralPath $b.Sidecar -Raw | ConvertFrom-Json
            $json.NativeKey = "$($json.NativeKey)Anders"
            $json | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $b.Sidecar
            $r = Restore-RegistryBackup $b.Id -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
            $r.Result | Should -Not -Be 'Succeeded'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'lehnt einen HKLM-Schlüssel in einer Sicherung des Benutzers ab (gehört nur in den Admin-Ordner)' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup -Root $script:MachineRoot
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Message.Code | Should -Be 'BackupMachineNotYet'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'lehnt ab, wenn der Schlüssel schon wieder existiert' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            New-Item -Path $b.Path -Force | Out-Null
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Unsupported'
            $r.Message.Code | Should -Be 'RestoreKeyExists'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'meldet einen Fehler, wenn reg import scheitert' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 1 }
            $b = New-TestBackup
            $r = Restore-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Message.Code | Should -Be 'RestoreBackupFailed'
        }

        It 'bricht ab, wenn sich die bestätigte Kennung geändert hat' {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $b = New-TestBackup
            $r = Restore-RegistryBackup $b.Id -Confirm:$false -ConfirmedCommandLine ([guid]::NewGuid().ToString())
            $r.Result | Should -Be 'Cancelled'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'findet Sicherungen nur über die Kennung, nie über einen Pfad (<Id>)' -TestCases @(
            @{ Id = '..\..\evil' }
            @{ Id = 'C:\Windows\win.ini' }
            @{ Id = '*' }
            @{ Id = '00000000-0000-0000-0000-000000000000' }
        ) {
            Mock -ModuleName SoftwareInventory Invoke-RegImport { 0 }
            $r = Restore-RegistryBackup $Id -Confirm:$false
            $r.Result | Should -Be 'NotInstalled'
            $r.Message.Code | Should -Be 'BackupNotFound'
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
        }

        It 'nimmt auch ein Objekt von Get-RegistryBackup aus der Pipeline' {
            $b = New-TestBackup
            $r = Get-RegistryBackup | Restore-RegistryBackup -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            Test-Path $b.Path | Should -BeTrue
        }
    }

    Context 'Remove-RegistryBackup' {
        It 'plant mit -WhatIf, ohne etwas zu löschen' {
            $b = New-TestBackup
            $plan = Remove-RegistryBackup $b.Id -WhatIf
            $plan.Result | Should -Be 'Planned'
            $plan.Action | Should -Be 'RemoveBackup'
            Test-Path $b.File | Should -BeTrue
            Test-Path $b.Sidecar | Should -BeTrue
        }

        It 'löscht .reg und .json zusammen und protokolliert; der Registry-Eintrag bleibt unberührt' {
            $b = New-TestBackup
            New-Item -Path $b.Path -Force | Out-Null
            $r = Remove-RegistryBackup $b.Id -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.Message.Code | Should -Be 'RemoveBackupDone'
            Test-Path $b.File | Should -BeFalse
            Test-Path $b.Sidecar | Should -BeFalse
            Test-Path $b.Path | Should -BeTrue
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            $log[-1].Action | Should -Be 'RemoveBackup'
            $log[-1].Result | Should -Be 'Succeeded'
        }

        It 'löscht auch ältere Sicherungen ohne Begleitdatei' {
            $b = New-TestBackup -NoSidecar
            (Remove-RegistryBackup $b.Id -Confirm:$false).Result | Should -Be 'Succeeded'
            Test-Path $b.File | Should -BeFalse
        }

        It 'meldet unbekannte Kennungen, ohne etwas zu löschen' {
            $b = New-TestBackup
            $r = Remove-RegistryBackup '..\..\evil' -Confirm:$false
            $r.Result | Should -Be 'NotInstalled'
            $r.Message.Code | Should -Be 'BackupNotFound'
            Test-Path $b.File | Should -BeTrue
        }

        It 'bricht ab, wenn sich die bestätigte Kennung geändert hat' {
            $b = New-TestBackup
            (Remove-RegistryBackup $b.Id -Confirm:$false -ConfirmedCommandLine ([guid]::NewGuid().ToString())).Result | Should -Be 'Cancelled'
            Test-Path $b.File | Should -BeTrue
        }
    }

    Context 'Sicherungen für alle Benutzer (HKLM, Admin-Ordner)' {
        BeforeEach {
            # Eine Sicherung wie vom Helfer: <Id>.reg und <Id>.json im (umgeleiteten) Admin-Ordner, Bereich Machine.
            function New-MachineBackup {
                param([string] $Name = 'Alt-Programm', [string] $Key = 'oldapp', [string] $SidecarScope = 'Machine', [int] $AgeDays = 0)
                $path = "$($script:MachineRoot)\$Key"
                New-Item -Path $path -Force | Out-Null
                New-ItemProperty -Path $path -Name DisplayName -Value $Name | Out-Null
                $native = (Get-Item -LiteralPath $path).Name
                $id = [guid]::NewGuid().ToString()
                New-Item -ItemType Directory -Path $script:MachineDir -Force | Out-Null
                $file = Join-Path $script:MachineDir "$id.reg"
                InModuleScope SoftwareInventory -Parameters @{ K = $native; F = $file } { Invoke-RegExport -NativeKey $K -File $F } | Should -Be 0
                InModuleScope SoftwareInventory -Parameters @{ F = $file; I = $id; N = $Name; K = $native; S = $SidecarScope } {
                    Write-RegistryBackupSidecar -File $F -ActionId $I -Name $N -NativeKey $K -Scope $S -Reasons @([pscustomobject] @{ Code = 'OrphanedEntry'; Args = @() })
                }
                Remove-Item -LiteralPath $path -Recurse -Force
                if ($AgeDays) { (Get-Item -LiteralPath $file).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-$AgeDays) }
                [pscustomobject] @{ Id = $id; File = $file; Native = $native; Path = $path; Sidecar = [System.IO.Path]::ChangeExtension($file, '.json') }
            }
            Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $false }
            Mock -ModuleName SoftwareInventory Invoke-RegImport { throw 'HKLM spielt nur der Helfer zurück' }
            $script:HelperMode = 'Done'
            $script:HelperPlans = [System.Collections.Generic.List[hashtable]]::new()
            Mock -ModuleName SoftwareInventory Start-ElevatedHelper {
                $script:HelperPlans.Add($HelperPlan)
                $message = { param($Code) [pscustomobject] @{ Code = $Code; Args = @(); Text = $Code } }
                $own = { param($Id) Get-ChildItem -LiteralPath $script:MachineDir -File | Where-Object { $_.Name -like "$Id.*" } }
                switch ($script:HelperMode) {
                    'Done' {
                        switch ($HelperPlan.Operation) {
                            'RestoreRegistryBackup' {
                                # Wie der Helfer: den Schlüssel aus der .json zurückspielen und ihn als NativeKey melden.
                                $key = (Get-Content -LiteralPath (Join-Path $script:MachineDir "$($HelperPlan.BackupId).json") -Raw | ConvertFrom-Json).NativeKey
                                New-Item -Path "$($script:MachineRoot)\oldapp" -Force | Out-Null
                                @{ Status = 'Completed'; Done = $true; NativeKey = $key }
                            }
                            'RemoveRegistryBackup' { & $own $HelperPlan.BackupId | Remove-Item -Force; @{ Status = 'Completed'; Done = $true; Deleted = 2 } }
                            'CleanupRegistryBackups' {
                                $old = @(Get-ChildItem -LiteralPath $script:MachineDir -File -Filter '*.reg' | Where-Object { $_.LastWriteTimeUtc -lt [datetime]::UtcNow.AddDays(-365) })
                                foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName, ([System.IO.Path]::ChangeExtension($f.FullName, '.json')) -Force }
                                @{ Status = 'Completed'; Done = $true; Deleted = 2 * $old.Count }
                            }
                        }
                    }
                    'ClaimsDone' { @{ Status = 'Completed'; Done = $true } }
                    'OtherKey' {
                        # Die .json wurde nach der Bestätigung geändert: Der Helfer spielt einen anderen Schlüssel zurück und meldet ihn;
                        # der bestätigte Schlüssel existiert trotzdem (zufällig).
                        New-Item -Path "$($script:MachineRoot)\oldapp" -Force | Out-Null
                        @{ Status = 'Completed'; Done = $true; NativeKey = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\fremd' }
                    }
                    'NoCount' {
                        # Räumt auf wie 'Done', meldet aber kein Feld Deleted.
                        $old = @(Get-ChildItem -LiteralPath $script:MachineDir -File -Filter '*.reg' | Where-Object { $_.LastWriteTimeUtc -lt [datetime]::UtcNow.AddDays(-365) })
                        foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName, ([System.IO.Path]::ChangeExtension($f.FullName, '.json')) -Force }
                        @{ Status = 'Completed'; Done = $true }
                    }
                    'RegOnly' {
                        # Löscht beim Aufräumen nur die abgelaufenen .reg, nicht ihre .json, und meldet trotzdem Erfolg.
                        Get-ChildItem -LiteralPath $script:MachineDir -File -Filter '*.reg' | Where-Object { $_.LastWriteTimeUtc -lt [datetime]::UtcNow.AddDays(-365) } | Remove-Item -Force
                        @{ Status = 'Completed'; Done = $true }
                    }
                    'Denied' { @{ Status = 'ElevationDenied'; Error = (& $message 'ElevationDenied') } }
                    'TooOld' { @{ Status = 'Failed'; Error = (& $message 'HelperTooOld') } }
                    'Partial' { @{ Status = 'Completed'; Done = $false; ErrorCode = 'RestorePartial'; Error = (& $message 'RestorePartial') } }
                }
            }
        }

        It 'listet beide Orte; HKLM-Sicherungen haben Bereich Machine und brauchen Administratorrechte' {
            $user = New-TestBackup
            $machine = New-MachineBackup
            $list = @(Get-RegistryBackup)
            $list.Count | Should -Be 2
            $m = $list | Where-Object Id -EQ $machine.Id
            $m.Scope | Should -Be 'Machine'
            $m.Elevated | Should -BeTrue
            $m.CanRestore | Should -BeTrue
            $m.Expired | Should -BeFalse
            ($list | Where-Object Id -EQ $user.Id).Scope | Should -Be 'User'
            $script:HelperPlans.Count | Should -Be 0 -Because 'die Liste braucht nie eine UAC-Abfrage'
        }

        It 'ignoriert im Admin-Ordner fremde Namen und die Zwischendateien des Helfers' {
            $machine = New-MachineBackup
            $id = [guid]::NewGuid().ToString()
            Copy-Item -LiteralPath $machine.File -Destination (Join-Path $script:MachineDir "${id}_Name.reg")
            Copy-Item -LiteralPath $machine.File -Destination (Join-Path $script:MachineDir "$id.import.reg")
            Copy-Item -LiteralPath $machine.File -Destination (Join-Path $script:MachineDir 'fremd.reg')
            @(Get-RegistryBackup).Id | Should -Be @($machine.Id)
        }

        It 'lehnt eine Begleitdatei mit Bereich "<SidecarScope>" im Admin-Ordner ab, ohne den Helfer zu starten' -TestCases @(
            @{ SidecarScope = 'User' }
            @{ SidecarScope = '' }
            @{ SidecarScope = 'machine' }
        ) {
            $machine = New-MachineBackup -SidecarScope $SidecarScope
            $item = Get-RegistryBackup -Id $machine.Id
            $item.CanRestore | Should -BeFalse
            $item.Problem | Should -Be 'MetadataInvalid'
            (Restore-RegistryBackup $machine.Id -Confirm:$false).Result | Should -Be 'Unsupported'
            $script:HelperPlans.Count | Should -Be 0 -Because 'eine Sicherung, die der Helfer ablehnen würde, braucht keine UAC-Abfrage'
        }

        It 'prüft die Begleitdatei im Admin-Ordner so streng wie der Helfer: <Case>' -TestCases @(
            @{ Case = 'gültig wie vom Helfer (Gegenprobe)'; From = $null; To = $null; Mode = 'Text'; Valid = $true }
            @{ Case = 'SchemaVersion als Zeichenkette'; From = '"SchemaVersion": 1,'; To = '"SchemaVersion": "1",'; Mode = 'Text'; Valid = $false }
            @{ Case = 'SchemaVersion als Kommazahl'; From = '"SchemaVersion": 1,'; To = '"SchemaVersion": 1.0,'; Mode = 'Text'; Valid = $false }
            @{ Case = 'Scope als Liste'; From = '"Scope": "Machine"'; To = '"Scope": ["Machine"]'; Mode = 'Text'; Valid = $false }
            @{ Case = 'NativeKey als Zahl'; From = '"NativeKey": "'; To = '"NativeKey": 1, "Unused": "'; Mode = 'Text'; Valid = $false }
            @{ Case = 'Feldname in anderer Schreibweise'; From = '"NativeKey"'; To = '"nativekey"'; Mode = 'Text'; Valid = $false }
            @{ Case = 'mit BOM'; From = $null; To = $null; Mode = 'Bom'; Valid = $false }
            @{ Case = 'ungültiges UTF-8'; From = $null; To = $null; Mode = 'BadUtf8'; Valid = $false }
        ) {
            $machine = New-MachineBackup -Name 'XX-Programm'
            $text = [ordered]@{
                SchemaVersion = 1; ActionId = $machine.Id; CreatedAt = '2026-11-20T10:00:00.0000000Z'; Name = 'XX-Programm'
                NativeKey = $machine.Native; Scope = 'Machine'; Reasons = @()
            } | ConvertTo-Json
            if ($From) { $text.Contains($From) | Should -BeTrue -Because 'der Ersatz muss greifen'; $text = $text.Replace($From, $To) }
            $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
            switch ($Mode) {
                'Bom' { $bytes = [byte[]] (@(0xEF, 0xBB, 0xBF) + $bytes) }
                'BadUtf8' {
                    # "XX" im Namen durch eine ungültige UTF-8-Folge (C3 28) ersetzen.
                    $at = [System.Text.Encoding]::ASCII.GetString($bytes).IndexOf('XX-Programm')
                    $bytes[$at] = 0xC3; $bytes[$at + 1] = 0x28
                }
            }
            [System.IO.File]::WriteAllBytes($machine.Sidecar, $bytes)
            $item = Get-RegistryBackup -Id $machine.Id
            $item.CanRestore | Should -Be $Valid
            if (-not $Valid) {
                $item.Problem | Should -Be 'MetadataInvalid'
                (Restore-RegistryBackup $machine.Id -Confirm:$false).Result | Should -Be 'Unsupported'
                $script:HelperPlans.Count | Should -Be 0
            }
        }

        It 'bleibt im Benutzerordner bei der bisherigen Prüfung (eine Begleitdatei mit BOM gilt dort weiter)' {
            $b = New-TestBackup
            $text = [System.IO.File]::ReadAllText($b.Sidecar)
            [System.IO.File]::WriteAllText($b.Sidecar, $text, [System.Text.UTF8Encoding]::new($true))
            (Get-RegistryBackup -Id $b.Id).CanRestore | Should -BeTrue
        }

        It 'überspringt im Admin-Ordner Dateien, die Links (Reparse-Points) sind' {
            $machine = New-MachineBackup
            $linkId = [guid]::NewGuid().ToString()
            $link = [pscustomobject] @{
                Name = "$linkId.reg"; Extension = '.reg'; FullName = (Join-Path $script:MachineDir "$linkId.reg")
                Attributes = [System.IO.FileAttributes]::Archive -bor [System.IO.FileAttributes]::ReparsePoint
            }
            Mock -ModuleName SoftwareInventory Get-ChildItem { @([System.IO.DirectoryInfo]::new($script:MachineDir).GetFiles()) + $link } -ParameterFilter {
                $LiteralPath -contains $script:MachineDir -and $PSBoundParameters['ErrorAction'] -ne 'Stop'
            }
            @(Get-RegistryBackup).Id | Should -Be @($machine.Id)
            Should -Invoke -ModuleName SoftwareInventory Get-ChildItem -ParameterFilter { $LiteralPath -contains $script:MachineDir }
        }

        It 'bricht <Action> ohne Helfer ab, wenn sich die bestätigte Angabe geändert hat' -TestCases @(
            @{ Action = 'Zurückspielen' }
            @{ Action = 'Löschen' }
        ) {
            $machine = New-MachineBackup
            $r = if ($Action -eq 'Zurückspielen') {
                Restore-RegistryBackup $machine.Id -Confirm:$false -ConfirmedCommandLine "$($machine.Id) HKEY_LOCAL_MACHINE\anders"
            }
            else { Remove-RegistryBackup $machine.Id -Confirm:$false -ConfirmedCommandLine ([guid]::NewGuid().ToString()) }
            $r.Result | Should -Be 'Cancelled'
            $script:HelperPlans.Count | Should -Be 0
            Test-Path $machine.File | Should -BeTrue
        }

        It 'führt <Action> unter der Kennung aus dem bestätigten Plan aus und lehnt eine benutzte Kennung ab' -TestCases @(
            @{ Action = 'Zurückspielen' }
            @{ Action = 'Löschen' }
            @{ Action = 'Aufräumen' }
        ) {
            $machine = New-MachineBackup -AgeDays 400
            $run = {
                param([switch] $WhatIf, [string] $Id, [string] $Line)
                $common = @{ WhatIf = $WhatIf }
                if (-not $WhatIf) { $common = @{ Confirm = $false; ConfirmedActionId = $Id; ConfirmedCommandLine = $Line } }
                switch ($Action) {
                    'Zurückspielen' { Restore-RegistryBackup $machine.Id @common }
                    'Löschen' { Remove-RegistryBackup $machine.Id @common }
                    'Aufräumen' { Clear-ExpiredRegistryBackup @common }
                }
            }
            $plan = & $run -WhatIf
            $plan.Result | Should -Be 'Planned'
            $r = & $run -Id $plan.ActionId -Line $plan.CommandLine
            $r.Result | Should -Be 'Succeeded'
            $r.ActionId | Should -Be $plan.ActionId
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            @($log.ActionId | Select-Object -Unique) | Should -Be @($plan.ActionId)

            # Dieselbe Kennung ein zweites Mal: abgebrochen, ohne Helfer.
            $machine = New-MachineBackup -Key 'zweit' -AgeDays 400
            $calls = $script:HelperPlans.Count
            $again = & $run -Id $plan.ActionId
            $again.Result | Should -Be 'Cancelled'
            $again.Message.Code | Should -Be 'ActionIdUsed'
            $script:HelperPlans.Count | Should -Be $calls
        }

        It 'lehnt eine Kennung ab, die keine GUID ist, ohne den Helfer zu starten' {
            $machine = New-MachineBackup
            $r = Restore-RegistryBackup $machine.Id -Confirm:$false -ConfirmedActionId 'C:\x'
            $r.Result | Should -Be 'Cancelled'
            $r.Message.Code | Should -Be 'ActionIdInvalid'
            $script:HelperPlans.Count | Should -Be 0
        }

        It 'gilt nicht als Erfolg, wenn der Helfer einen anderen Schlüssel als den bestätigten zurückgespielt hat' {
            $machine = New-MachineBackup
            $plan = Restore-RegistryBackup $machine.Id -WhatIf
            $script:HelperMode = 'OtherKey'
            $r = Restore-RegistryBackup $machine.Id -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
            $r.Result | Should -Be 'Failed'
            $r.Message.Code | Should -Be 'BackupResultNotVerified'
            $r.PresentAfter | Should -BeTrue -Because 'der bestätigte Schlüssel existiert, trotzdem kein Erfolg'
        }

        It 'erkennt den gemeldeten Schlüssel ohne Rücksicht auf Groß-/Kleinschreibung als den bestätigten' {
            $machine = New-MachineBackup
            Mock -ModuleName SoftwareInventory Start-ElevatedHelper {
                New-Item -Path "$($script:MachineRoot)\oldapp" -Force | Out-Null
                @{ Status = 'Completed'; Done = $true; NativeKey = $machine.Native.ToUpperInvariant() }
            }
            (Restore-RegistryBackup $machine.Id -Confirm:$false).Result | Should -Be 'Succeeded'
        }

        It 'plant das Zurückspielen erhöht, ohne Wiederherstellungspunkt und ohne Helfer' {
            $machine = New-MachineBackup
            $plan = Restore-RegistryBackup $machine.Id -WhatIf
            $plan.Result | Should -Be 'Planned'
            $plan.Elevated | Should -BeTrue
            $plan.Message.Code | Should -Be 'PlanRestoreBackupMachine'
            $script:HelperPlans.Count | Should -Be 0
        }

        It 'spielt über den Helfer zurück: nur Operation, Kennung und kein Wiederherstellungspunkt' {
            $machine = New-MachineBackup
            $plan = Restore-RegistryBackup $machine.Id -WhatIf
            $r = Restore-RegistryBackup $machine.Id -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
            $r.Result | Should -Be 'Succeeded'
            $r.Message.Code | Should -Be 'RestoreBackupDone'
            $r.PresentAfter | Should -BeTrue
            $script:HelperPlans.Count | Should -Be 1
            $sent = $script:HelperPlans[0]
            $sent.Operation | Should -BeExactly 'RestoreRegistryBackup'
            $sent.BackupId | Should -Be $machine.Id
            $sent.RestorePoint | Should -BeFalse
            @($sent.Keys | Sort-Object) | Should -Be @('BackupId', 'Operation', 'RestorePoint')
            Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
            $log = Get-ChildItem -LiteralPath (Join-Path $script:AppDir 'logs\actions') -Filter '*.jsonl' | Get-Content | ForEach-Object { $_ | ConvertFrom-Json }
            $log.Phase | Should -Be @('Started', 'Completed')
        }

        It 'meldet <Mode> beim Zurückspielen ehrlich' -TestCases @(
            @{ Mode = 'Denied'; Result = 'ElevationDenied'; Code = 'ElevationDenied' }
            @{ Mode = 'TooOld'; Result = 'Failed'; Code = 'HelperTooOld' }
            @{ Mode = 'Partial'; Result = 'Failed'; Code = 'RestorePartial' }
            @{ Mode = 'ClaimsDone'; Result = 'Failed'; Code = 'BackupResultNotVerified' }
        ) {
            $machine = New-MachineBackup
            $script:HelperMode = $Mode
            $r = Restore-RegistryBackup $machine.Id -Confirm:$false
            $r.Result | Should -Be $Result
            $r.Message.Code | Should -Be $Code
        }

        It 'spielt nicht zurück, wenn der Schlüssel schon existiert (64-Bit-Prüfung wie der Helfer)' {
            $machine = New-MachineBackup
            New-Item -Path $machine.Path -Force | Out-Null
            $r = Restore-RegistryBackup $machine.Id -Confirm:$false
            $r.Message.Code | Should -Be 'RestoreKeyExists'
            $script:HelperPlans.Count | Should -Be 0
        }

        It 'löscht über den Helfer und prüft danach selbst, dass .reg und .json weg sind' {
            $machine = New-MachineBackup
            $plan = Remove-RegistryBackup $machine.Id -WhatIf
            $plan.Message.Code | Should -Be 'PlanRemoveBackupMachine'
            $r = Remove-RegistryBackup $machine.Id -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            Test-Path $machine.File | Should -BeFalse
            Test-Path $machine.Sidecar | Should -BeFalse
            $script:HelperPlans[0].Operation | Should -BeExactly 'RemoveRegistryBackup'

            $machine = New-MachineBackup -Key 'second'
            $script:HelperMode = 'ClaimsDone'
            $r = Remove-RegistryBackup $machine.Id -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Message.Code | Should -Be 'BackupResultNotVerified'
        }

        It 'meldet den Zustand des Admin-Ordners und die Zahl abgelaufener Sicherungen' {
            (Get-RegistryBackupStatus).MachineFolderState | Should -Be 'Missing'
            $null = New-MachineBackup
            $null = New-MachineBackup -Key 'alt' -AgeDays 400
            $status = Get-RegistryBackupStatus
            $status.MachineFolderState | Should -Be 'Readable'
            $status.ExpiredMachineCount | Should -Be 1
            $status.RetentionDays | Should -Be 365
            (@(Get-RegistryBackup) | Where-Object Expired).Count | Should -Be 1
            $script:HelperPlans.Count | Should -Be 0 -Because 'Zustand und Liste lesen nur, ohne UAC-Abfrage'
        }

        It 'meldet einen nicht lesbaren Admin-Ordner und räumt dann nicht auf' {
            $null = New-MachineBackup -Key 'alt' -AgeDays 400
            Mock -ModuleName SoftwareInventory Get-ChildItem { throw [System.UnauthorizedAccessException]::new('Zugriff verweigert') } -ParameterFilter {
                $LiteralPath -contains $script:MachineDir -and $PSBoundParameters['ErrorAction'] -eq 'Stop'
            }
            $status = Get-RegistryBackupStatus
            $status.MachineFolderState | Should -Be 'Unreadable'
            $status.ExpiredMachineCount | Should -Be 0
            $r = Clear-ExpiredRegistryBackup -Confirm:$false
            $r.Result | Should -Be 'Unsupported'
            $r.Message.Code | Should -Be 'BackupFolderUnreadable'
            $script:HelperPlans.Count | Should -Be 0
        }

        It 'meldet ElevationDenied beim <Action> und lässt die Dateien stehen' -TestCases @(
            @{ Action = 'Löschen' }
            @{ Action = 'Aufräumen' }
        ) {
            $machine = New-MachineBackup -Key 'alt' -AgeDays 400
            $script:HelperMode = 'Denied'
            $r = if ($Action -eq 'Löschen') { Remove-RegistryBackup $machine.Id -Confirm:$false } else { Clear-ExpiredRegistryBackup -Confirm:$false }
            $r.Result | Should -Be 'ElevationDenied'
            $r.Message.Code | Should -Be 'ElevationDenied'
            Test-Path $machine.File | Should -BeTrue
            Test-Path $machine.Sidecar | Should -BeTrue
        }

        It 'gilt beim Aufräumen nicht als Erfolg, wenn die .json einer abgelaufenen Sicherung übrig bleibt' {
            $old = New-MachineBackup -Key 'alt' -AgeDays 400
            $script:HelperMode = 'RegOnly'
            $r = Clear-ExpiredRegistryBackup -Confirm:$false
            $r.Result | Should -Be 'Failed'
            $r.Message.Code | Should -Be 'BackupResultNotVerified'
            $r.PresentAfter | Should -BeTrue
            Test-Path $old.Sidecar | Should -BeTrue
        }

        It 'räumt abgelaufene Sicherungen nur auf Bestätigung über den Helfer auf' {
            $fresh = New-MachineBackup
            $old = New-MachineBackup -Key 'alt' -AgeDays 400
            $plan = Clear-ExpiredRegistryBackup -WhatIf
            $plan.Result | Should -Be 'Planned'
            $plan.Elevated | Should -BeTrue
            $plan.Message.Code | Should -Be 'PlanClearExpiredBackups'
            $plan.Message.Args[0] | Should -Be 1
            $script:HelperPlans.Count | Should -Be 0

            $r = Clear-ExpiredRegistryBackup -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
            $r.Result | Should -Be 'Succeeded'
            $r.Message.Code | Should -Be 'ClearExpiredBackupsDone'
            $script:HelperPlans[0].Operation | Should -BeExactly 'CleanupRegistryBackups'
            @($script:HelperPlans[0].Keys | Sort-Object) | Should -Be @('Operation', 'RestorePoint')
            Test-Path $old.File | Should -BeFalse
            Test-Path $fresh.File | Should -BeTrue
            $entry = @(Get-ActionLog -Action ClearExpiredBackups)
            $entry.Count | Should -Be 1
            $entry[0].Result | Should -Be 'Succeeded'
        }

        It 'meldet beim Aufräumen 0 gelöschte Dateien, wenn der Helfer keine Anzahl liefert' {
            $null = New-MachineBackup -Key 'alt' -AgeDays 400
            $script:HelperMode = 'NoCount'
            $r = Clear-ExpiredRegistryBackup -Confirm:$false
            $r.Result | Should -Be 'Succeeded'
            $r.Message.Code | Should -Be 'ClearExpiredBackupsDone'
            $r.Message.Args[0] | Should -Be 0
        }

        It 'tut beim Aufräumen nichts, wenn nichts abgelaufen ist, und bricht bei geändertem Ordner ab' {
            $null = New-MachineBackup
            $r = Clear-ExpiredRegistryBackup -Confirm:$false
            $r.Result | Should -Be 'NotInstalled'
            $r.Message.Code | Should -Be 'ClearExpiredBackupsNothing'
            $script:HelperPlans.Count | Should -Be 0

            $null = New-MachineBackup -Key 'alt' -AgeDays 400
            (Clear-ExpiredRegistryBackup -Confirm:$false -ConfirmedCommandLine 'C:\anders').Result | Should -Be 'Cancelled'
            $script:HelperPlans.Count | Should -Be 0
        }
    }
}

Describe 'Sicherungen: .reg und .json in der Selbstbereinigung' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive "cleanup-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
        $script:Backup = Join-Path $script:Root 'logs\registry-backup'
        New-Item -ItemType Directory -Path $script:Backup -Force | Out-Null
        function New-Pair([string] $Name, [int] $AgeDays) {
            $reg = Join-Path $script:Backup "$Name.reg"; $json = Join-Path $script:Backup "$Name.json"
            'x' | Set-Content -LiteralPath $reg, $json
            foreach ($f in $reg, $json) { (Get-Item $f).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-$AgeDays) }
            $reg, $json
        }
        function Invoke-Cleanup { InModuleScope SoftwareInventory -Parameters @{ R = $script:Root } { Invoke-AppDataCleanup -RetentionDays 30 -MaxSizeMB 1 -Root $R } | Out-Null }
    }

    It 'löscht ein altes Paar gemeinsam und behält ein junges Paar' {
        $old = New-Pair 'alt' 400
        $recent = New-Pair 'jung' 100
        Invoke-Cleanup
        Test-Path $old[0] | Should -BeFalse
        Test-Path $old[1] | Should -BeFalse
        Test-Path $recent[0] | Should -BeTrue
        Test-Path $recent[1] | Should -BeTrue
    }

    It 'trennt ein Paar nie: Das Alter bestimmt die .reg, auch wenn die .json älter wirkt' {
        $pair = New-Pair 'gemischt' 100
        (Get-Item $pair[1]).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-500)
        Invoke-Cleanup
        Test-Path $pair[0] | Should -BeTrue
        Test-Path $pair[1] | Should -BeTrue
    }

    It 'löscht eine alte .reg samt .json, auch wenn die .json jünger ist' {
        $pair = New-Pair 'alt2' 400
        (Get-Item $pair[1]).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-1)
        Invoke-Cleanup
        Test-Path $pair[0] | Should -BeFalse
        Test-Path $pair[1] | Should -BeFalse
    }

    It 'löscht eine .json ohne .reg erst nach einem Tag' {
        $fresh = Join-Path $script:Backup 'frisch.json'; $stale = Join-Path $script:Backup 'rest.json'
        'x' | Set-Content -LiteralPath $fresh, $stale
        (Get-Item $stale).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-3)
        Invoke-Cleanup
        Test-Path $fresh | Should -BeTrue
        Test-Path $stale | Should -BeFalse
    }
}

Describe 'Test-RegistryBackupContent: gemeinsame Fälletabelle mit dem Helfer' {
    BeforeDiscovery {
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-backup-cases.json" | ConvertFrom-Json
        $SharedCases = @($table.cases | ForEach-Object { @{ Name = $_.name; Scope = $_.scope; Key = $_.key; Text = $_.text; Expected = $_.expected } })
    }

    BeforeAll {
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-backup-cases.json" | ConvertFrom-Json
        $script:SharedHeader = $table.header
        $script:SharedPlaceholders = @($table.locations | ForEach-Object { @{ Placeholder = $_.placeholder; Path = $_.nativePath } })
        $locations = @($table.locations | ForEach-Object { [pscustomobject] @{ NativePath = $_.nativePath; Scope = $_.scope } })
        $script:SharedUninstallLocations = $locations
        Mock -ModuleName SoftwareInventory Get-UninstallLocationNative { $script:SharedUninstallLocations }
        function Expand-CaseText([string] $Text) {
            $t = $Text.Replace('{H}', $script:SharedHeader)
            foreach ($p in $script:SharedPlaceholders) { $t = $t.Replace($p.Placeholder, $p.Path) }
            # {U+XXXX} wird zum Zeichen mit diesem Codepunkt (unsichtbare Zeichen stehen in der Tabelle nie als Escape-Text).
            [regex]::Replace($t, '\{U\+([0-9A-Fa-f]{4})\}', { param($m) [string] [char] [Convert]::ToInt32($m.Groups[1].Value, 16) })
        }
    }

    It 'liefert für "<Name>" das Ergebnis der Tabelle' -ForEach $SharedCases {
        $text = Expand-CaseText $Text
        $key = Expand-CaseText $Key
        $actual = InModuleScope SoftwareInventory -Parameters @{ T = $text; K = $key; S = $Scope } { Test-RegistryBackupContent -Text $T -NativeKey $K -Scope $S }
        if ($Expected) { $actual | Should -BeExactly $Expected } else { $actual | Should -BeNullOrEmpty }
    }

    It 'enthält genug Fälle' {
        $script:SharedPlaceholders.Count | Should -Be 3
        (Get-Content -Raw "$PSScriptRoot/../Data/registry-backup-cases.json" | ConvertFrom-Json).cases.Count | Should -BeGreaterThan 25
    }

    It 'liest die Bytes einer Sicherung wie der Helfer (fileCases der Tabelle)' {
        $table = Get-Content -Raw "$PSScriptRoot/../Data/registry-backup-cases.json" | ConvertFrom-Json
        $table.fileCases.Count | Should -BeGreaterThan 8
        foreach ($case in $table.fileCases) {
            $bytes = [byte[]] [System.Convert]::FromHexString([string] $case.hex)
            $result = InModuleScope SoftwareInventory -Parameters @{ B = $bytes } { ConvertFrom-RegistryBackupByte -Bytes $B }
            $expectedCode = if ($case.PSObject.Properties['expectedCode']) { $case.expectedCode }
            if ($expectedCode) { $result.Problem | Should -BeExactly $expectedCode -Because $case.name }
            else {
                $result.Problem | Should -BeNullOrEmpty -Because $case.name
                $result.Text | Should -BeExactly (Expand-CaseText ([string] $case.expectedText)) -Because $case.name
            }
        }
    }

    It 'lehnt eine Sicherung über 16 MB ab, auch mit gültiger BOM' {
        $big = [byte[]]::new(16MB + 2)
        $big[0] = 0xFF; $big[1] = 0xFE
        (InModuleScope SoftwareInventory -Parameters @{ B = $big } { ConvertFrom-RegistryBackupByte -Bytes $B }).Problem | Should -Be 'TooLarge'
    }
}
