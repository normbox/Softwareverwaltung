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
