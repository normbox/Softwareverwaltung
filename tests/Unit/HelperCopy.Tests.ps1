BeforeAll {
    Import-Module "$PSScriptRoot/../../src/SoftwareInventory" -Force
}

Describe 'Geschützte Kopie des Helfers' {
    BeforeEach {
        InModuleScope SoftwareInventory {
            $script:root = Join-Path $TestDrive ('pf' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '\Softwareverwaltung\Helper')
            $script:version = [string] (Get-SoftwareInventoryVersion)
            $script:copy = Join-Path $script:root "$script:version\SoftwareInventory.Helper.exe"
            $script:sourceDir = Join-Path $TestDrive ('app' + [guid]::NewGuid().ToString('N').Substring(0, 6))
            New-Item -ItemType Directory -Path $script:sourceDir | Out-Null
            $script:source = Join-Path $script:sourceDir 'SoftwareInventory.Helper.exe'
            Set-Content -LiteralPath $script:source -Value 'quelle' -NoNewline
            $script:savedHelperPath = $script:ElevatedHelperPath
            $script:ElevatedHelperPath = $script:source

            function script:Write-TestCopy([string] $Path, [string] $Content = 'quelle') {
                New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
                Set-Content -LiteralPath $Path -Value $Content -NoNewline
            }

            Mock Get-HelperCopyRoot { $script:root }
            # Nur die Quelle im App-Ordner ist beschreibbar.
            Mock Test-UserWritablePath { $Path -eq $script:source }
            Mock Test-HelperDebugBuild { $true }
            Mock Test-HelperSignatureValid { $false }
            Mock Write-ActionLogEntry { }
            Mock Invoke-ElevatedSystemTool { throw 'nicht erwartet' }
            Mock Start-Sleep { }
        }
    }

    AfterEach {
        InModuleScope SoftwareInventory { $script:ElevatedHelperPath = $script:savedHelperPath }
    }

    Context 'Prüfung am Zielort' {
        It 'Debug-Build erkennt eine Kopie mit gleichem Hash an' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                Test-HelperCopyTrusted -Path $script:copy -Source $script:source | Should -BeTrue
            }
        }

        It 'Debug-Build lehnt einen anderen Hash ab' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy 'anders'
                Test-HelperCopyTrusted -Path $script:copy -Source $script:source | Should -BeFalse
            }
        }

        It 'Release lehnt trotz gleichem Hash ab, wenn die Signatur fehlt' {
            InModuleScope SoftwareInventory {
                Mock Test-HelperDebugBuild { $false }
                Write-TestCopy $script:copy
                Test-HelperCopyTrusted -Path $script:copy -Source $script:source | Should -BeFalse
            }
        }

        It 'Release zählt ausschließlich die Signatur, der Hash spielt keine Rolle' {
            InModuleScope SoftwareInventory {
                Mock Test-HelperDebugBuild { $false }
                Mock Test-HelperSignatureValid { $true }
                Mock Get-FileHash { throw 'im Release darf kein Hash gerechnet werden' }
                Write-TestCopy $script:copy 'anders'
                Test-HelperCopyTrusted -Path $script:copy -Source $script:source | Should -BeTrue
            }
        }

        It 'lehnt beschreibbare Ordner ab: <Case>' -TestCases @(
            @{ Case = 'Datei'; Target = 'copy' }
            @{ Case = 'Versionsordner'; Target = 'dir' }
            @{ Case = 'Helfer-Ordner'; Target = 'root' }
        ) {
            InModuleScope SoftwareInventory -Parameters @{ T = $Target } {
                Write-TestCopy $script:copy
                $script:writable = switch ($T) { 'copy' { $script:copy } 'dir' { Split-Path -Parent $script:copy } 'root' { $script:root } }
                Mock Test-UserWritablePath { $Path -eq $script:writable }
                Test-HelperCopyTrusted -Path $script:copy -Source $script:source | Should -BeFalse
            }
        }

        It 'lehnt Pfade außerhalb des Helfer-Ordners ab' {
            InModuleScope SoftwareInventory {
                Test-HelperCopyTrusted -Path $script:source -Source $script:source | Should -BeFalse
            }
        }
    }

    Context 'Auswahl der Exe' {
        It 'nimmt ohne Erhöhung immer die Exe im App-Ordner' {
            InModuleScope SoftwareInventory {
                (Resolve-ElevatedHelperPath -NoElevation).Path | Should -Be $script:source
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }

        It 'braucht keine Kopie, wenn der App-Ordner geschützt ist' {
            InModuleScope SoftwareInventory {
                Mock Test-UserWritablePath { $false }
                $r = Resolve-ElevatedHelperPath
                $r.Path | Should -Be $script:source
                $r.IsCopy | Should -BeFalse
            }
        }

        It 'startet eine anerkannte Kopie ohne weitere Abfrage' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                $r = Resolve-ElevatedHelperPath
                $r.Path | Should -Be $script:copy
                $r.IsCopy | Should -BeTrue
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }

        It 'legt die Kopie mit robocopy aus System32 an und prüft sie danach' {
            InModuleScope SoftwareInventory {
                Mock Invoke-ElevatedSystemTool { Write-TestCopy $script:copy; 1 }
                $r = Resolve-ElevatedHelperPath
                $r.Path | Should -Be $script:copy
                Should -Invoke Invoke-ElevatedSystemTool -Times 1 -Exactly -ParameterFilter { $Tool -eq 'robocopy.exe' -and $Arguments -like "*SoftwareInventory.Helper.exe /R:1*" }
                Should -Invoke Write-ActionLogEntry -Times 1 -Exactly -ParameterFilter { $Data.Action -eq 'CreateHelperCopy' -and $Data.Result -eq 'Succeeded' }
            }
        }

        It 'startet die Kopie nicht, wenn sie die Prüfung am Zielort nicht besteht' {
            InModuleScope SoftwareInventory {
                Mock Invoke-ElevatedSystemTool { Write-TestCopy $script:copy 'manipuliert'; 1 }
                $r = Resolve-ElevatedHelperPath
                $r.Path | Should -Be $script:source
                $r.IsCopy | Should -BeFalse
                Should -Invoke Write-ActionLogEntry -Times 1 -Exactly -ParameterFilter { $Data.Result -eq 'Failed' -and $Data.Message.Code -eq 'HelperCopyCheckFailed' }
            }
        }

        It 'bleibt beim App-Ordner, wenn robocopy scheitert' {
            InModuleScope SoftwareInventory {
                Mock Invoke-ElevatedSystemTool { 8 }
                (Resolve-ElevatedHelperPath).Path | Should -Be $script:source
                Should -Invoke Write-ActionLogEntry -Times 1 -Exactly -ParameterFilter { $Data.Message.Code -eq 'HelperCopyCreateFailed' }
            }
        }

        It 'meldet eine abgelehnte UAC-Abfrage' {
            InModuleScope SoftwareInventory {
                Mock Invoke-ElevatedSystemTool { throw [System.ComponentModel.Win32Exception]::new(1223) }
                (Resolve-ElevatedHelperPath).Status | Should -Be 'ElevationDenied'
            }
        }

        It 'fragt im Release ohne gültige Signatur gar nicht erst nach' {
            InModuleScope SoftwareInventory {
                Mock Test-HelperDebugBuild { $false }
                (Resolve-ElevatedHelperPath).Path | Should -Be $script:source
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }

        It 'überschreibt eine nicht anerkannte Kopie nicht' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy 'alter Debug-Build'
                (Resolve-ElevatedHelperPath).Path | Should -Be $script:source
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }

        It 'meldet einen fehlenden Helfer' {
            InModuleScope SoftwareInventory {
                Remove-Item -LiteralPath $script:source
                (Resolve-ElevatedHelperPath).Error.Code | Should -Be 'HelperFileMissing'
            }
        }

        It 'tauscht im Release nur über die geschützte alte Exe aus' {
            InModuleScope SoftwareInventory {
                Mock Test-HelperDebugBuild { $false }
                Mock Test-HelperSignatureValid { $true }
                $script:older = Join-Path $script:root '0.0.1\SoftwareInventory.Helper.exe'
                Write-TestCopy $script:older 'alt'
                Mock Start-ElevatedHelper { Write-TestCopy $script:copy 'neu'; @{ Status = 'Completed'; Error = $null } }
                $r = Resolve-ElevatedHelperPath
                $r.Path | Should -Be $script:copy
                Should -Invoke Start-ElevatedHelper -Times 1 -Exactly -ParameterFilter { $HelperPath -eq $script:older -and $HelperPlan.Operation -eq 'ReplaceHelperCopy' -and $HelperPlan.TargetVersion -eq $script:version }
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }

        It 'startet die neue Kopie nicht, wenn der Austausch abgelehnt wurde' {
            InModuleScope SoftwareInventory {
                Mock Test-HelperDebugBuild { $false }
                Mock Test-HelperSignatureValid { $true }
                Write-TestCopy (Join-Path $script:root '0.0.1\SoftwareInventory.Helper.exe') 'alt'
                Mock Start-ElevatedHelper { @{ Status = 'Completed'; Error = (New-InventoryMessage HelperCopyPublisherMismatch) } }
                (Resolve-ElevatedHelperPath).Path | Should -Be $script:source
            }
        }
    }

    Context 'Warnung im Bestätigungsdialog' {
        It 'entfällt mit anerkannter Kopie' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                Test-HelperInWritableFolder | Should -BeFalse
            }
        }

        It 'bleibt ohne Kopie' {
            InModuleScope SoftwareInventory { Test-HelperInWritableFolder | Should -BeTrue }
        }
    }

    Context 'Remove-HelperCopy' {
        It 'löscht den ganzen Helfer-Ordner ohne AutoRun und protokolliert' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                Mock Invoke-ElevatedSystemTool { Remove-Item -LiteralPath $script:root -Recurse -Force; 0 }
                $r = Remove-HelperCopy -Confirm:$false
                $r.Result | Should -Be 'Removed'
                Should -Invoke Invoke-ElevatedSystemTool -Times 1 -Exactly -ParameterFilter { $Tool -eq 'cmd.exe' -and $Arguments -like "/d /c rd /s /q `"$($script:root)`" & rd *" }
                Should -Invoke Write-ActionLogEntry -Times 1 -Exactly -ParameterFilter { $Data.Action -eq 'RemoveHelperCopy' -and $Data.Result -eq 'Succeeded' }
            }
        }

        It 'meldet eine abgelehnte Abfrage' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                Mock Invoke-ElevatedSystemTool { throw [System.ComponentModel.Win32Exception]::new(1223) }
                (Remove-HelperCopy -Confirm:$false).Result | Should -Be 'ElevationDenied'
            }
        }

        It 'meldet Fehlschlag, wenn der Ordner bleibt' {
            InModuleScope SoftwareInventory {
                Write-TestCopy $script:copy
                Mock Invoke-ElevatedSystemTool { 0 }
                (Remove-HelperCopy -Confirm:$false).Result | Should -Be 'Failed'
            }
        }

        It 'fragt nichts ab, wenn keine Kopie da ist' {
            InModuleScope SoftwareInventory {
                (Remove-HelperCopy -Confirm:$false).Result | Should -Be 'NotPresent'
                Should -Invoke Invoke-ElevatedSystemTool -Times 0
            }
        }
    }

    It 'Native-DLL erkennt Debug nur über das Build-Symbol' {
        $code = Get-Content "$PSScriptRoot/../../src/SoftwareInventory.Native/BuildInfo.cs" -Raw
        $code | Should -Match '#if DEBUG\s+public static bool IsDebugBuild => true;\s+#else\s+public static bool IsDebugBuild => false;'
    }
}
