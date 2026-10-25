<#
.SYNOPSIS
    Startet die veröffentlichte App in Windows Sandbox und hält das Ergebnis fest – nur in der Sandbox ausführen!
.DESCRIPTION
    Läuft unter Windows PowerShell 5.1. Prüft, dass weder .NET noch PowerShell 7 noch winget
    vorhanden sind, kopiert die App wie ein Benutzer nach %LOCALAPPDATA%\Programs und startet sie:
      1. ohne Einstellungen (erwartet: Hinweise „Keine Quelle aktiviert“ und „winget nicht verfügbar“)
      2. mit aktivierten lokalen Quellen (erwartet: Liste mit Programmen)
    Bildschirmfotos und ergebnis-app-<Zeit>.json landen in C:\Out.
#>
$ErrorActionPreference = 'Stop'
if ($env:USERNAME -ne 'WDAGUtilityAccount') {
    throw 'Nur in Windows Sandbox ausführen (Start-AppSandbox.ps1).'
}

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SandboxWindow {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    public struct RECT { public int Left, Top, Right, Bottom; }
}
'@

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$checks = New-Object System.Collections.Generic.List[object]
function Add-Check {
    param([string] $Step, [bool] $Ok, [string] $Detail)
    $checks.Add([pscustomobject] @{ Step = $Step; Ok = $Ok; Detail = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} – {2}" -f $(if ($Ok) { 'OK ' } else { 'FEHLER' }), $Step, $Detail) -ForegroundColor $color
}

function Save-WindowImage {
    param([System.Diagnostics.Process] $Process, [string] $Name)
    $Process.Refresh()
    $handle = $Process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) { return $null }
    [SandboxWindow]::SetForegroundWindow($handle) | Out-Null
    Start-Sleep -Milliseconds 500
    $rect = New-Object SandboxWindow+RECT
    [SandboxWindow]::GetWindowRect($handle, [ref] $rect) | Out-Null
    $bitmap = New-Object System.Drawing.Bitmap ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    [SandboxWindow]::PrintWindow($handle, $hdc, 2) | Out-Null
    $graphics.ReleaseHdc($hdc)
    $file = Join-Path 'C:\Out' "app-$stamp-$Name.png"
    $bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
    $file
}

function Invoke-AppRun {
    param([string] $Name, [int] $WaitSeconds)
    Write-Host "Starte App ($Name) und warte $WaitSeconds Sekunden ..."
    $process = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds $WaitSeconds
    if ($process.HasExited) {
        Add-Check "App läuft ($Name)" $false ('beendet mit Exit-Code 0x{0:X8}' -f $process.ExitCode)
        # Absturzursache aus der Ereignisanzeige (Application Error, .NET Runtime) mitnehmen.
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $process.StartTime } -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -in 'Application Error', '.NET Runtime', 'Windows Error Reporting' } |
            Select-Object TimeCreated, ProviderName, Id, Message |
            Format-List | Out-String -Width 300 | Set-Content -LiteralPath (Join-Path 'C:\Out' "absturz-$stamp-$Name.txt") -Encoding UTF8
        return
    }
    $image = Save-WindowImage -Process $process -Name $Name
    Add-Check "App läuft ($Name)" ([bool] $image) $(if ($image) { "Bild: $(Split-Path $image -Leaf)" } else { 'kein Fenster gefunden' })
    $process.CloseMainWindow() | Out-Null
    if (-not $process.WaitForExit(10000)) { $process.Kill() }
}

# 1. Voraussetzungen: Es darf nichts davon installiert sein.
$dotnet = Test-Path (Join-Path $env:ProgramFiles 'dotnet\shared\Microsoft.WindowsDesktop.App')
$pwsh = [bool] (Get-Command pwsh.exe -ErrorAction SilentlyContinue)
$winget = [bool] (Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.InstallLocation 'winget.exe') })
Add-Check 'Keine .NET-Desktop-Laufzeit installiert' (-not $dotnet) "vorhanden: $dotnet"
Add-Check 'Kein PowerShell 7 installiert' (-not $pwsh) "vorhanden: $pwsh"
Write-Host "winget vorhanden: $winget (erwartet: nein, die App soll dann einen Hinweis zeigen)"

# 2. App wie ein Benutzer kopieren.
$target = Join-Path $env:LOCALAPPDATA 'Programs\Softwareverwaltung'
# Zielordner vorher anlegen: Fehlt er, kopiert Copy-Item den Inhalt sonst eine Ebene zu hoch.
New-Item -ItemType Directory -Path $target -Force | Out-Null
Copy-Item -Path 'C:\Repo\artifacts\publish\Softwareverwaltung\*' -Destination $target -Recurse -Force
$exe = Join-Path $target 'Softwareverwaltung.exe'
Add-Check 'App kopiert' (Test-Path -LiteralPath $exe) $exe
if (-not (Test-Path -LiteralPath $exe)) { throw "App nicht gefunden: $exe" }

# 3. Ohne Einstellungen.
Invoke-AppRun -Name 'ohne-einstellungen' -WaitSeconds 30

# 4. Mit aktivierten lokalen Quellen (Einstellungsdatei wie Set-InventorySetting sie schreibt).
$settingsDir = Join-Path $env:APPDATA 'SoftwareInventory'
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
@{ SchemaVersion = 1; Sources = @{ RegistryMachine = $true; RegistryUser = $true; Winget = $true; Appx = $true } } |
    ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $settingsDir 'settings.json') -Encoding UTF8
Invoke-AppRun -Name 'mit-quellen' -WaitSeconds 45

# 5. Keine Logs der App im Temp-Ordner (siehe CLAUDE.md „Logs räumen sich selbst auf“).
$tempLogs = @(Get-ChildItem -LiteralPath $env:TEMP -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*SoftwareInventory*' -or $_.Name -like '*Softwareverwaltung*' })
Add-Check 'Keine App-Logs im Temp-Ordner' ($tempLogs.Count -eq 0) (($tempLogs | Select-Object -First 3 -ExpandProperty FullName) -join ', ')

$file = Join-Path 'C:\Out' "ergebnis-app-$stamp.json"
[pscustomobject] @{ Checks = $checks; WingetPresent = $winget } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
$failed = @($checks | Where-Object { -not $_.Ok }).Count
Write-Host ''
Write-Host "$($checks.Count - $failed) von $($checks.Count) Prüfungen bestanden. Ergebnis: $file" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
Write-Host 'Fertig. Die Sandbox kann jetzt geschlossen werden; die Ergebnisse bleiben in tests\Sandbox\out.'
