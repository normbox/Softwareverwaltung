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
        $json | ConvertTo-Json | Set-Content -LiteralPath $b.Sidecar
        $r = Restore-RegistryBackup $b.Id -Confirm:$false -ConfirmedCommandLine $plan.CommandLine
        $r.Result | Should -Not -Be 'Succeeded'
        Should -Invoke -ModuleName SoftwareInventory Invoke-RegImport -Times 0 -Exactly
    }

    It 'lehnt Einträge für alle Benutzer (HKLM) ab' {
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
            $t
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
}
