BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
    $script:HelperPath = "$PSScriptRoot/../../src/SoftwareInventory/Elevated/ElevatedHelper.ps1"
    $script:System = [Environment]::GetFolderPath('System')
    $script:IsElevated = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
}

Describe 'Helferskript: Wiederherstellungspunkt' {
    BeforeAll {
        . $HelperPath
    }

    It 'meldet Created, wenn ein neuer Punkt entstanden ist' {
        $script:seq = 5
        Mock Get-CimInstance { [pscustomobject] @{ SequenceNumber = $script:seq } }
        Mock Invoke-CimMethod { $script:seq = 6; [pscustomobject] @{ ReturnValue = 0 } }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'Created'
        Should -Invoke Invoke-CimMethod -Times 1 -ParameterFilter { $Namespace -eq 'root/default' -and $ClassName -eq 'SystemRestore' -and $MethodName -eq 'CreateRestorePoint' }
    }

    It 'meldet Skipped mit Hinweis auf die 24-Stunden-Grenze, wenn Windows keinen Punkt anlegt' {
        Mock Get-CimInstance { [pscustomobject] @{ SequenceNumber = 5 } }
        Mock Invoke-CimMethod { [pscustomobject] @{ ReturnValue = 0 } }
        Mock Test-SystemProtectionDisabled { $false }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'Skipped'
        $r.Code | Should -Be 'RestorePointNotCreated'
    }

    It 'meldet NotAvailable, wenn der Computerschutz aus ist' {
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { [pscustomobject] @{ ReturnValue = 0 } }
        Mock Test-SystemProtectionDisabled { $true }
        (Invoke-RestorePoint -Description 'Test' -Type 1).Status | Should -Be 'NotAvailable'
    }

    It 'meldet NotAvailable bei deaktiviertem Dienst (1058)' {
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { [pscustomobject] @{ ReturnValue = 1058 } }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'NotAvailable'
        $r.Code | Should -Be 'RestorePointProtectionOff'
    }

    It 'meldet NotAvailable, wenn der deaktivierte Dienst als Ausnahme kommt (0x80070422)' {
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { throw [System.Runtime.InteropServices.COMException]::new('Dienst deaktiviert', -2147023838) }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'NotAvailable'
        $r.Code | Should -Be 'RestorePointProtectionOffDetail'
        $r.Args | Should -Be @('Dienst deaktiviert')
    }

    It 'erkennt vorzeichenlose HRESULTs und nennt unbekannte Codes in der Meldung' {
        Get-ExceptionErrorCode ([System.Runtime.InteropServices.COMException]::new('x', -2147023838)) | Should -Contain -2147023838
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { throw [System.Runtime.InteropServices.COMException]::new('anders', -2147024891) }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'Failed'
        $r.Code | Should -Be 'RestorePointFailedDetail'
        $r.Args[1] | Should -Match '0x80070005'
    }

    It 'meldet NotAvailable bei Win32-Fehler 1058 als Ausnahme' {
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { throw [System.ComponentModel.Win32Exception]::new(1058) }
        (Invoke-RestorePoint -Description 'Test' -Type 1).Status | Should -Be 'NotAvailable'
    }

    It 'meldet NotAvailable, wenn die Klasse fehlt' {
        Mock Get-CimInstance { throw 'Ungültige Klasse' }
        (Invoke-RestorePoint -Description 'Test' -Type 1).Status | Should -Be 'NotAvailable'
    }

    It 'meldet Failed bei anderen Fehlern' {
        Mock Get-CimInstance { @() }
        Mock Invoke-CimMethod { [pscustomobject] @{ ReturnValue = 5 } }
        (Invoke-RestorePoint -Description 'Test' -Type 1).Status | Should -Be 'Failed'
        Mock Invoke-CimMethod { throw 'Zugriff verweigert' }
        $r = Invoke-RestorePoint -Description 'Test' -Type 1
        $r.Status | Should -Be 'Failed'
        $r.Code | Should -Be 'RestorePointFailedDetail'
        $r.Args[0] | Should -Match 'Zugriff verweigert'
    }
}

Describe 'Helferskript: Prüfungen' {
    BeforeAll {
        . $HelperPath
    }

    It 'akzeptiert Programme außerhalb von Benutzer- und Temp-Ordnern' {
        Test-HelperFilePath (Join-Path $System 'msiexec.exe') | Should -BeNullOrEmpty
    }

    It 'lehnt Benutzer- und Temp-Ordner sowie relative Pfade ab' {
        (Test-HelperFilePath "$env:SystemDrive\Users\Public\x.exe").Code | Should -Be 'HelperPathInUserFolder'
        (Test-HelperFilePath "$env:windir\Temp\x.exe").Code | Should -Be 'HelperPathInUserFolder'
        (Test-HelperFilePath 'x.exe').Code | Should -Be 'HelperPathNotAbsolute'
    }

    It 'erlaubt Programme im Benutzerordner nur ohne Erhöhung (HKCU-Programme)' {
        $exe = Join-Path $TestDrive 'unins000.exe'
        Set-Content -LiteralPath $exe -Value 'x'
        (Test-HelperFilePath $exe).Code | Should -Be 'HelperPathInUserFolder'
        (Test-HelperFilePath $exe -Elevated $true).Code | Should -Be 'HelperPathInUserFolder'
        Test-HelperFilePath $exe -Elevated $false | Should -BeNullOrEmpty
    }

    It 'lehnt winget außerhalb von WindowsApps mit klarer Meldung ab' {
        (Test-HelperFilePath "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe").Code | Should -Be 'HelperWingetNotFound'
    }

    It 'lässt sich von Windows PowerShell 5.1 fehlerfrei parsen (UTF-8 mit BOM)' {
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $HelperPath))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        $count = & "$System\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "`$e=`$null; [void][Management.Automation.Language.Parser]::ParseFile('$((Resolve-Path $HelperPath).Path)', [ref]`$null, [ref]`$e); `$e.Count"
        $count | Should -Be '0'
    }

    It 'entfernt Fortschrittsbalken und Drehstriche aus der Ausgabe' {
        $text = "Gefunden 7-Zip [7zip.7zip]`r`n   -`r   \`r   |`r`n  ██████▒▒▒▒  1.2 MB / 2.0 MB`r`nErfolgreich installiert`r`n"
        Get-OutputTail $text | Should -Be "Gefunden 7-Zip [7zip.7zip]`nErfolgreich installiert"
    }
}

Describe 'Start-ElevatedHelper' {
    It 'führt den Helfer unter Windows PowerShell 5.1 aus und liefert Exit-Code und Ausgabe über die Pipe' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 60 -HelperPlan @{ FilePath = (Join-Path $S 'where.exe'); Arguments = 'cmd.exe'; MsiLog = $false; RestorePoint = $false }
        }
        $r.Status | Should -Be 'Completed'
        $r.PowerShellVersion | Should -BeLike '5.1*'
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'cmd\.exe'
        $r.Error | Should -BeNullOrEmpty
    }

    It 'meldet den Exit-Code eines fehlschlagenden Programms' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 60 -HelperPlan @{ FilePath = (Join-Path $S 'where.exe'); Arguments = '/q gibt-es-nicht-123.exe'; MsiLog = $false; RestorePoint = $false }
        }
        $r.ExitCode | Should -Be 1
    }

    It 'meldet eine Zeitüberschreitung, ohne das Programm zu beenden' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 1 -HelperPlan @{ FilePath = (Join-Path $S 'timeout.exe'); Arguments = '/t 3 /nobreak'; MsiLog = $false; RestorePoint = $false }
        }
        $r.TimedOut | Should -BeTrue
        $r.ExitCode | Should -BeNullOrEmpty
    }

    It 'führt nichts aus, wenn das Helferskript verändert wurde (Hash)' {
        Mock -ModuleName SoftwareInventory Get-FileHash { [pscustomobject] @{ Hash = '00' * 32 } }
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 30 -HelperPlan @{ FilePath = (Join-Path $S 'where.exe'); Arguments = 'cmd.exe'; MsiLog = $false; RestorePoint = $false }
        }
        $r.Status | Should -Be 'Failed'
        $r.Error.Code | Should -Be 'HelperExitedWithoutResult'
        $r.Error.Args | Should -Be @(3)
    }

    It 'meldet ElevationDenied, wenn die UAC-Abfrage abgelehnt wird' {
        Mock -ModuleName SoftwareInventory Start-ElevatedProcess {
            throw [System.InvalidOperationException]::new('abgebrochen', [System.ComponentModel.Win32Exception]::new(1223))
        }
        $r = InModuleScope SoftwareInventory { Start-ElevatedHelper -HelperPlan @{ FilePath = 'x'; RestorePoint = $false } }
        $r.Status | Should -Be 'ElevationDenied'
    }

    It 'verwirft Ergebnisse von einem anderen Prozess als dem gestarteten Helfer' {
        Mock -ModuleName SoftwareInventory Start-ElevatedProcess {
            # Statt des Helfers verbindet sich dieser Testprozess selbst mit der Pipe.
            $pipeName = ([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(($ArgumentList -replace "(?s).*-PlanBase64 '([^']+)'.*", '$1'))) | ConvertFrom-Json).PipeName
            # Eigener Runspace: Die Pipe hat keinen Puffer, Schreiben wartet auf den Leser.
            $script:fakeClient = [powershell]::Create().AddScript({
                    param($Name)
                    $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $Name, [System.IO.Pipes.PipeDirection]::Out)
                    $client.Connect(5000)
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"Nonce":"falsch","ExitCode":0}')
                    try { $client.Write($bytes, 0, $bytes.Length) } catch { $null = $_ }
                    $client.Dispose()
                }).AddArgument($pipeName)
            [void] $script:fakeClient.BeginInvoke()
            [pscustomobject] @{ Id = 1; HasExited = $false; ExitCode = $null }
        }
        $r = InModuleScope SoftwareInventory { Start-ElevatedHelper -NoElevation -TimeoutSeconds 5 -HelperPlan @{ FilePath = 'x'; RestorePoint = $false } }
        $r.Status | Should -Be 'Failed'
        $r.Error.Code | Should -Be 'HelperUnexpectedProcess'
    }

    It 'lässt Prozesse ohne Adminrechte nicht an die Pipe' {
        if ($IsElevated) { Set-ItResult -Skipped -Because 'Test läuft mit Adminrechten'; return }
        $name = "SoftwareInventory-test-$([guid]::NewGuid().ToString('N'))"
        $server = InModuleScope SoftwareInventory -Parameters @{ N = $name } { New-ResultPipe -Name $N }
        try {
            $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $name, [System.IO.Pipes.PipeDirection]::Out)
            $denied = $null
            try { $client.Connect(1000) } catch { $denied = $_.Exception.GetBaseException() }
            $denied | Should -BeOfType [System.UnauthorizedAccessException]
            $client.Dispose()
        }
        finally {
            $server.Dispose()
        }
    }
}

Describe 'Helferskript: Abbrechen' {
    BeforeAll {
        . $HelperPath
        function New-FakeProcess {
            $p = [pscustomobject] @{ Id = 42; Killed = 0 }
            $p | Add-Member ScriptMethod Kill { $this.Killed++ }
            $p | Add-Member ScriptMethod WaitForExit { param($ms) $true }
            $p
        }
    }

    It 'beendet nie ein anderes Programm als winget' {
        Mock Get-CimInstance { @() }
        $p = New-FakeProcess
        Request-HelperCancel -Process $p -FilePath 'C:\Windows\System32\msiexec.exe' | Should -Be 'Continuing'
        $p.Killed | Should -Be 0
    }

    It 'beendet winget nicht, wenn schon ein Installer läuft' {
        Mock Get-CimInstance { [pscustomobject] @{ Name = 'conhost.exe' }; [pscustomobject] @{ Name = 'setup.exe' } }
        $p = New-FakeProcess
        Request-HelperCancel -Process $p -FilePath 'C:\Program Files\WindowsApps\x\winget.exe' | Should -Be 'Continuing'
        $p.Killed | Should -Be 0
    }

    It 'beendet winget, solange nur conhost als Kindprozess da ist' {
        Mock Get-CimInstance { [pscustomobject] @{ Name = 'conhost.exe' } }
        $p = New-FakeProcess
        Request-HelperCancel -Process $p -FilePath 'C:\Program Files\WindowsApps\x\winget.exe' | Should -Be 'Stopped'
        $p.Killed | Should -Be 1
    }

    It 'meldet ehrlich, wenn der Installer gerade noch gestartet wurde' {
        $script:queries = 0
        Mock Get-CimInstance { $script:queries++; if ($script:queries -gt 1) { [pscustomobject] @{ Name = 'setup.exe' } } }
        $p = New-FakeProcess
        Request-HelperCancel -Process $p -FilePath 'C:\Program Files\WindowsApps\x\winget.exe' | Should -Be 'Orphaned'
    }

    It 'lässt die Aktion weiterlaufen, wenn die Prüfung scheitert' {
        Mock Get-CimInstance { throw 'WMI nicht verfügbar' }
        $p = New-FakeProcess
        Request-HelperCancel -Process $p -FilePath 'C:\Program Files\WindowsApps\x\winget.exe' | Should -Be 'Continuing'
        $p.Killed | Should -Be 0
    }
}

Describe 'Start-ElevatedHelper: Handschlag und Abbrechen' {
    It 'startet nichts, wenn schon vor dem Start abgebrochen wurde' {
        Mock -ModuleName SoftwareInventory Start-ElevatedProcess { throw 'darf nicht laufen' }
        $r = InModuleScope SoftwareInventory {
            Start-ElevatedHelper -Control ([hashtable]::Synchronized(@{ State = 'Cancelled' })) -HelperPlan @{ FilePath = 'x'; RestorePoint = $false }
        }
        $r.Status | Should -Be 'Cancelled'
        $r.Error.Code | Should -Be 'ActionCancelledBeforeStart'
    }

    It 'führt nichts aus, wenn während der UAC-Abfrage abgebrochen wurde' {
        $marker = Join-Path $TestDrive 'lief.txt'
        Mock -ModuleName SoftwareInventory Set-ActionPhase { if ($Control) { $Control['State'] = 'Cancelled' } }
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System; M = $marker } {
            $control = [hashtable]::Synchronized(@{ State = 'Running' })
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 60 -Control $control -HelperPlan @{ FilePath = (Join-Path $S 'cmd.exe'); Arguments = "/c echo x>`"$M`""; MsiLog = $false; RestorePoint = $false }
        }
        $r.Status | Should -Be 'Cancelled'
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'lässt einen laufenden Installer weiterlaufen und meldet Continuing' {
        $marker = Join-Path $TestDrive 'laeuft.txt'
        $control = [hashtable]::Synchronized(@{ State = 'Running' })
        # Eigener Runspace: bricht ab, sobald das Programm läuft.
        $canceller = [powershell]::Create().AddScript({
                param($C, $M)
                $end = [datetime]::UtcNow.AddSeconds(30)
                while (-not (Test-Path -LiteralPath $M) -and [datetime]::UtcNow -lt $end) { Start-Sleep -Milliseconds 50 }
                $C['State'] = 'Cancelled'
            }).AddArgument($control).AddArgument($marker)
        [void] $canceller.BeginInvoke()
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System; M = $marker; C = $control } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 60 -Control $C -HelperPlan @{ FilePath = (Join-Path $S 'cmd.exe'); Arguments = "/c echo x>`"$M`"& ping -n 4 127.0.0.1>nul"; MsiLog = $false; RestorePoint = $false }
        }
        $canceller.Dispose()
        $r.Status | Should -Be 'Completed'
        $r.ExitCode | Should -Be 0
        $r.Cancelled | Should -BeFalse
        $control['CancelResult'] | Should -Be 'Continuing'
    }

    It 'wertet einen Abbruch als Ergebnis Cancelled aus' {
        InModuleScope SoftwareInventory {
            $result = [pscustomobject] @{ Output = $null; InstallerLog = $null; ExitCode = $null; ExitCodeHex = $null }
            $stopped = Read-HelperRun -Result $result -Run @{ Status = 'Completed'; Cancelled = $true; ExitCode = -1 } -TimeoutMinutes 60
            $stopped.Failure[0] | Should -Be 'Cancelled'
            $stopped.Failure[1].Code | Should -Be 'ActionCancelledDuringDownload'
            $before = Read-HelperRun -Result $result -Run @{ Status = 'Cancelled'; Error = (New-InventoryMessage ActionCancelledBeforeStart) } -TimeoutMinutes 60
            $before.Failure[0] | Should -Be 'Cancelled'
        }
    }

    It 'startet mit UAC über die Native-DLL und meldet Fehler als Win32-Code' {
        $missing = Join-Path $TestDrive 'gibt-es-nicht.exe'
        $failure = $null
        try { [void] [SoftwareInventory.ElevationInterop]::Start($missing, '', [IntPtr]::Zero) } catch { $failure = $_.Exception.GetBaseException() }
        $failure | Should -BeOfType [System.ComponentModel.Win32Exception]
        $failure.NativeErrorCode | Should -Be 2
    }
}

Describe 'Update-IncompleteActionLog' {
    BeforeEach {
        $appData = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock -ModuleName SoftwareInventory Get-AppDataDirectory { $appData }
        function Write-Started {
            param([string] $Id = 'a1', [string] $Action = 'Update')
            InModuleScope SoftwareInventory -Parameters @{ I = $Id; A = $Action } {
                Write-ActionLogEntry -Phase Started -Data ([ordered]@{ ActionId = $I; Action = $A; Name = 'Contoso Tool'; RegistryKey = 'HKLM:\X'; VersionBefore = '1.0'; Result = $null })
            }
        }
        function Set-InstalledState { param($Present, $Version)
            $script:state = [pscustomobject] @{ Present = $Present; Version = $Version; Identity = 'Registry'; WingetVersion = $null }
            Mock -ModuleName SoftwareInventory Get-InstalledState { $script:state }
        }
    }

    It 'trägt ein erreichtes Update sofort nach' {
        Write-Started
        Set-InstalledState $true '2.0'
        $r = @(Update-IncompleteActionLog)
        $r.Count | Should -Be 1
        $log = Get-ActionLog
        $log.Result | Should -Be 'Interrupted'
        $log.VersionAfter | Should -Be '2.0'
        $log.Message.Code | Should -Be 'ActionInterruptedReached'
    }

    It 'trägt eine erfolgte Deinstallation nach' {
        Write-Started -Action Uninstall
        Set-InstalledState $false $null
        Update-IncompleteActionLog | Out-Null
        (Get-ActionLog).Message.Code | Should -Be 'ActionInterruptedRemoved'
    }

    It 'lässt eine junge Aktion ohne Änderung offen, sie kann noch laufen' {
        Write-Started
        Set-InstalledState $true '1.0'
        @(Update-IncompleteActionLog).Count | Should -Be 0
        (Get-ActionLog).Result | Should -Be 'Incomplete'
    }

    It 'meldet ohne Änderung nach der Wartezeit ehrlich „nicht erkennbar“' {
        Write-Started
        Set-InstalledState $true '1.0'
        @(Update-IncompleteActionLog -WaitMinutes 0).Count | Should -Be 1
        $log = Get-ActionLog
        $log.Result | Should -Be 'Interrupted'
        $log.Message.Code | Should -Be 'ActionInterruptedUnknown'
    }

    It 'wertet einen nicht lesbaren Zustand nicht als entfernt' {
        Write-Started -Action Uninstall
        $script:state = [pscustomobject] @{ Present = $false; Version = $null; Identity = $null; WingetVersion = $null }
        Mock -ModuleName SoftwareInventory Get-InstalledState { $script:state }
        @(Update-IncompleteActionLog).Count | Should -Be 0
    }

    It 'fasst abgeschlossene Aktionen nicht an und trägt jede nur einmal nach' {
        Write-Started
        Set-InstalledState $true '2.0'
        Update-IncompleteActionLog | Out-Null
        @(Update-IncompleteActionLog).Count | Should -Be 0
    }
}

Describe 'Telemetrie im erhöhten Helfer' {
    It 'schaltet die PowerShell-Telemetrie aus, bevor der Helfer läuft' {
        $cmd = InModuleScope SoftwareInventory { Get-ElevatedHelperBootstrap -HelperPath 'C:\x\h.ps1' -Hash 'AB' -PlanBase64 'cGxhbg==' }
        $cmd | Should -BeLike "`$env:POWERSHELL_TELEMETRY_OPTOUT='1';*"
    }
}
Describe 'Start-ElevatedHelperBatch' {
    It 'führt mehrere Schritte in einem Helfer aus und meldet jeden Schritt sofort' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            $where = Join-Path $S 'where.exe'
            $seen = [System.Collections.Generic.List[object]]::new()
            $steps = @(
                @{ FilePath = $where; Arguments = 'cmd.exe'; MsiLog = $false; TimeoutSeconds = 60 }
                @{ FilePath = $where; Arguments = '/q gibt-es-nicht-123.exe'; MsiLog = $false; TimeoutSeconds = 60 }
            )
            $batch = Start-ElevatedHelperBatch -NoElevation -Steps $steps -BeforeStep { param($i) $true } -AfterStep { param($i, $run) $seen.Add(@{ Index = $i; ExitCode = $run.ExitCode; Output = $run.Output; PowerShell = $run.PowerShellVersion }) }
            @{ Batch = $batch; Seen = @($seen) }
        }
        $r.Batch.Status | Should -Be 'Completed'
        $r.Batch.Done | Should -Be 2
        $r.Seen.Index | Should -Be @(0, 1)
        $r.Seen[0].ExitCode | Should -Be 0
        $r.Seen[0].Output | Should -Match 'cmd\.exe'
        $r.Seen[1].ExitCode | Should -Not -Be 0
        $r.Seen[0].PowerShell | Should -BeLike '5.1*'
    }

    It 'beendet den Stapel, wenn vor einem Schritt abgebrochen wird' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            $where = Join-Path $S 'where.exe'
            $seen = [System.Collections.Generic.List[int]]::new()
            $steps = @(1..3 | ForEach-Object { @{ FilePath = $where; Arguments = 'cmd.exe'; MsiLog = $false; TimeoutSeconds = 60 } })
            $batch = Start-ElevatedHelperBatch -NoElevation -Steps $steps -BeforeStep { param($i) $i -lt 1 } -AfterStep { param($i, $run) $seen.Add($i) }
            @{ Batch = $batch; Seen = @($seen) }
        }
        $r.Batch.Status | Should -Be 'Completed'
        $r.Batch.Done | Should -Be 1
        $r.Seen | Should -Be @(0)
    }

    It 'prüft jeden Schritt wie einen Einzelaufruf' {
        $r = InModuleScope SoftwareInventory {
            $runs = [System.Collections.Generic.List[object]]::new()
            $steps = @(@{ FilePath = 'relativ.exe'; Arguments = ''; MsiLog = $false; TimeoutSeconds = 60 })
            $null = Start-ElevatedHelperBatch -NoElevation -Steps $steps -BeforeStep { param($i) $true } -AfterStep { param($i, $run) $runs.Add($run) }
            $runs[0]
        }
        $r.Error.Code | Should -Be 'HelperPathNotAbsolute'
        $r.Started | Should -BeFalse
    }
}