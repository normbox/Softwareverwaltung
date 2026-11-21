<#
.SYNOPSIS
    Prüft in Windows Sandbox, dass die cmd-Zeile von Remove-AppData (Admin-Teil) keinen Junctions oder Links folgt.
.DESCRIPTION
    Nur in Windows Sandbox ausführen (startet über Start-RdJunctionSandbox.ps1). Lädt nur
    src\SoftwareInventory\Private\AppData.ps1 und baut die Befehlszeile mit Get-AppMachineRemovalCommand, also genau
    wie das Modul; ausgeführt wird sie erhöht (das Sandbox-Konto ist Administrator) im echten Program Files.
    Fall 1: Helper und RegistryBackup mit Junctions und einem Verzeichnis-Symlink auf C:\SandboxZiel, dazu eine fremde
    Datei direkt in Softwareverwaltung. Erwartet: Ziel unverändert, beide Unterordner weg, Softwareverwaltung bleibt.
    Fall 2: ohne fremde Datei. Erwartet: Softwareverwaltung ist danach weg.
    Ergebnis in der Konsole und in C:\Out\rd-junction-<Zeit>.txt. Ausgabe nur ASCII (Windows PowerShell 5.1).
#>
$ErrorActionPreference = 'Stop'
$lines = [System.Collections.Generic.List[string]]::new()
$failed = 0
function Write-Line([string] $Text) { $lines.Add($Text); Write-Host $Text }
function Test-Expect([string] $Name, [bool] $Ok) {
    if ($Ok) { Write-Line "  OK    $Name" } else { Write-Line "  FEHLT $Name"; $script:failed++ }
}

$principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Line 'FEHLGESCHLAGEN: Das Skript laeuft nicht mit Administratorrechten.'
    return
}

. 'C:\Repo\src\SoftwareInventory\Private\AppData.ps1'
$root = [System.IO.Path]::Combine([Environment]::GetFolderPath('ProgramFiles'), 'Softwareverwaltung')
$target = 'C:\SandboxZiel'

function Invoke-RemovalCommand {
    $arguments = Get-AppMachineRemovalCommand -Root $root
    Write-Line "  cmd.exe $arguments"
    $info = [System.Diagnostics.ProcessStartInfo]::new((Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'), $arguments)
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WorkingDirectory = [Environment]::GetFolderPath('System')
    $process = [System.Diagnostics.Process]::Start($info)
    $process.WaitForExit()
    Write-Line "  Exit-Code $($process.ExitCode)"
}

function New-Case([switch] $Foreign) {
    if (Test-Path -LiteralPath $root) { cmd.exe /d /c rd /s /q "`"$root`"" | Out-Null }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'wichtig.txt') -Value 'muss bleiben'
    New-Item -ItemType Directory -Path (Join-Path $target 'Unterordner') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $target 'Unterordner\auch.txt') -Value 'muss bleiben'
    New-Item -ItemType Directory -Path (Join-Path $root 'Helper\0.1.0') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root 'Helper\0.1.0\SoftwareInventory.Helper.exe') -Value 'x'
    New-Item -ItemType Junction -Path (Join-Path $root 'Helper\junction') -Target $target | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $root 'Helper\symlink') -Target $target | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root 'RegistryBackup') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root "RegistryBackup\$([guid]::NewGuid()).reg") -Value 'x'
    New-Item -ItemType Junction -Path (Join-Path $root 'RegistryBackup\junction') -Target $target | Out-Null
    if ($Foreign) { Set-Content -LiteralPath (Join-Path $root 'Softwareverwaltung.exe') -Value 'fremd' }
}

function Test-TargetIntact {
    Test-Expect 'Ziel C:\SandboxZiel\wichtig.txt ist noch da' (Test-Path -LiteralPath (Join-Path $target 'wichtig.txt'))
    Test-Expect 'Ziel C:\SandboxZiel\Unterordner\auch.txt ist noch da' (Test-Path -LiteralPath (Join-Path $target 'Unterordner\auch.txt'))
}

Write-Line "Pruefung rd /s mit Junctions ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))"
Write-Line 'Fall 1: mit fremder Datei in Softwareverwaltung'
New-Case -Foreign
Invoke-RemovalCommand
Test-TargetIntact
Test-Expect 'Helper ist weg' (-not (Test-Path -LiteralPath (Join-Path $root 'Helper')))
Test-Expect 'RegistryBackup ist weg' (-not (Test-Path -LiteralPath (Join-Path $root 'RegistryBackup')))
Test-Expect 'Softwareverwaltung bleibt wegen der fremden Datei' (Test-Path -LiteralPath (Join-Path $root 'Softwareverwaltung.exe'))

Write-Line 'Fall 2: ohne fremde Datei'
New-Case
Invoke-RemovalCommand
Test-TargetIntact
Test-Expect 'Softwareverwaltung ist weg' (-not (Test-Path -LiteralPath $root))

if ($failed) { Write-Line "FEHLGESCHLAGEN ($failed Pruefungen)" } else { Write-Line 'BESTANDEN' }
$out = 'C:\Out'
if (Test-Path -LiteralPath $out) {
    $file = Join-Path $out ("rd-junction-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [System.IO.File]::WriteAllLines($file, $lines)
    Write-Host "Ergebnis gespeichert: $file"
}
