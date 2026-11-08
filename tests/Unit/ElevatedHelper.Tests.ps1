BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
    $script:System = [Environment]::GetFolderPath('System')
    $script:IsElevated = ([System.Security.Principal.WindowsPrincipal] [System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
}

Describe 'Start-ElevatedHelper' {
    BeforeEach {
        # Keine echte Kopie und keine UAC-Abfrage in den Tests.
        Mock -ModuleName SoftwareInventory Test-UserWritablePath { $false }
    }

    It 'führt den Helfer aus und liefert Exit-Code und Ausgabe über die Pipe' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            Start-ElevatedHelper -NoElevation -TimeoutSeconds 60 -HelperPlan @{ FilePath = (Join-Path $S 'where.exe'); Arguments = 'cmd.exe'; MsiLog = $false; RestorePoint = $false }
        }
        $r.Status | Should -Be 'Completed'
        $r.HelperVersion | Should -Be 4
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

    It 'meldet einen fehlenden Helfer mit eigenem Code (z. B. Quarantäne)' {
        $r = InModuleScope SoftwareInventory {
            $original = $script:ElevatedHelperPath
            $script:ElevatedHelperPath = Join-Path $TestDrive 'fehlt.exe'
            try { Start-ElevatedHelper -NoElevation -HelperPlan @{ FilePath = 'x'; RestorePoint = $false } }
            finally { $script:ElevatedHelperPath = $original }
        }
        $r.Status | Should -Be 'Failed'
        $r.Error.Code | Should -Be 'HelperFileMissing'
    }

    It 'gibt auf der Kommandozeile nur den Namen der Pipe weiter' {
        Mock -ModuleName SoftwareInventory Start-ElevatedProcess { $script:seenArguments = $ArgumentList; throw 'Ende' }
        InModuleScope SoftwareInventory { $null = Start-ElevatedHelper -HelperPlan @{ FilePath = 'C:\geheim\x.exe'; Arguments = '/geheim'; RestorePoint = $false } }
        $script:seenArguments | Should -Match '^--pipe SoftwareInventory-[0-9a-f]{32}$'
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
            $pipeName = $ArgumentList -replace '^--pipe\s+', ''
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

Describe 'Start-ElevatedHelperBatch' {
    It 'führt mehrere Schritte in einem Helfer aus und meldet jeden Schritt sofort' {
        $r = InModuleScope SoftwareInventory -Parameters @{ S = $System } {
            $where = Join-Path $S 'where.exe'
            $seen = [System.Collections.Generic.List[object]]::new()
            $steps = @(
                @{ FilePath = $where; Arguments = 'cmd.exe'; MsiLog = $false; TimeoutSeconds = 60 }
                @{ FilePath = $where; Arguments = '/q gibt-es-nicht-123.exe'; MsiLog = $false; TimeoutSeconds = 60 }
            )
            $batch = Start-ElevatedHelperBatch -NoElevation -Steps $steps -BeforeStep { param($i) $true } -AfterStep { param($i, $run) $seen.Add(@{ Index = $i; ExitCode = $run.ExitCode; Output = $run.Output; HelperVersion = $run.HelperVersion }) }
            @{ Batch = $batch; Seen = @($seen) }
        }
        $r.Batch.Status | Should -Be 'Completed'
        $r.Batch.Done | Should -Be 2
        $r.Seen.Index | Should -Be @(0, 1)
        $r.Seen[0].ExitCode | Should -Be 0
        $r.Seen[0].Output | Should -Match 'cmd\.exe'
        $r.Seen[1].ExitCode | Should -Not -Be 0
        $r.Seen[0].HelperVersion | Should -Be 4
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

Describe 'Hinweis auf den beschreibbaren Ordner' {
    BeforeAll {
        $script:record = [pscustomobject] @{ Name = 'Contoso'; WingetId = 'Contoso.Tool'; WingetSource = 'winget' }
        $script:state = [pscustomobject] @{
            Present = $true; Version = '1.0'; Scope = 'Machine'; RegistryKey = $null; ProductCode = $null; UninstallString = $null
            QuietUninstallString = $null; UrlUpdateInfo = $null; UrlInfoAbout = $null; PackageFullName = $null; WingetVersion = '1.0'; Identity = 'Winget'
        }
        Mock -ModuleName SoftwareInventory Get-WingetExecutable { 'C:\Program Files\WindowsApps\x\winget.exe' }
        Mock -ModuleName SoftwareInventory Resolve-WingetTargetId { @{ Id = 'Contoso.Tool'; Local = $false } }
    }

    It 'warnt bei erhöhten Aktionen, wenn der Helfer beschreibbar liegt' {
        Mock -ModuleName SoftwareInventory Get-InstalledState { $script:state }
        Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $true }
        $plan = InModuleScope SoftwareInventory -Parameters @{ R = $record } { New-ActionPlan -Action Update -Record $R }
        $plan.Elevated | Should -BeTrue
        $plan.HelperInWritableFolder | Should -BeTrue
    }

    It 'warnt nicht, wenn der Helfer geschützt liegt' {
        Mock -ModuleName SoftwareInventory Get-InstalledState { $script:state }
        Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $false }
        (InModuleScope SoftwareInventory -Parameters @{ R = $record } { New-ActionPlan -Action Update -Record $R }).HelperInWritableFolder | Should -BeFalse
    }

    It 'warnt nicht bei Aktionen ohne Adminrechte' {
        $userState = $script:state.PSObject.Copy(); $userState.Scope = 'User'
        Mock -ModuleName SoftwareInventory Get-InstalledState { $userState }
        Mock -ModuleName SoftwareInventory Test-HelperInWritableFolder { $true }
        (InModuleScope SoftwareInventory -Parameters @{ R = $record } { New-ActionPlan -Action Update -Record $R }).HelperInWritableFolder | Should -BeFalse
    }
}
