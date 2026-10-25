<#
.SYNOPSIS
    Integrationstest für Update-Software und Uninstall-Software – nur in Windows Sandbox ausführen!
.DESCRIPTION
    Phase „Setup“ (Windows PowerShell 5.1, startet automatisch):
      lädt PowerShell 7 und winget in festen Versionen von den offiziellen GitHub-Releases,
      prüft SHA256 (fest hinterlegt) und bei der MSI zusätzlich die Microsoft-Signatur,
      installiert beides und startet Phase „Test“. MSIX-Pakete prüft Add-AppxPackage selbst.
    Phase „Test“ (PowerShell 7):
      installiert Testprogramme über winget und spielt Aktualisieren und Deinstallieren über
      alle Methoden durch (winget mit/ohne Adminrechte, MSI, QuietUninstallString, Store-App).
      Ergebnis: Tabelle in der Konsole und C:\Out\ergebnis-<Zeit>.json.
    Die Sandbox ist nach dem Schließen vollständig verworfen.
#>
param(
    [ValidateSet('Setup', 'Test')]
    [string] $Phase = 'Setup'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Feste Versionen und Prüfsummen (aus den GitHub-Release-Daten, Stand 25.10.2026).
$Downloads = @(
    @{ Name = 'PowerShell-7.6.8-win-x64.msi'
        Url = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.8/PowerShell-7.6.8-win-x64.msi'
        Sha256 = '079E7CECEDD1E87FA7B4676E5C33DDFBE66859A44A97FBCD1DB797245CBB93D2'; Signed = $true }
    @{ Name = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        Url = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
        Sha256 = '65DEA9C01CE08EE7B763366B27C0E651F97DB857C11CA9B9C301826C10092F2E'; Signed = $false }
    @{ Name = 'DesktopAppInstaller_Dependencies.zip'
        Url = 'https://github.com/microsoft/winget-cli/releases/download/v1.29.380/DesktopAppInstaller_Dependencies.zip'
        Sha256 = 'BA875AFE9D190F61218985AC0292A99D1DB710BF93E13C68944CA9D89F0D82D1'; Signed = $false }
)
$WingetClientVersion = '1.29.380'

function Get-VerifiedDownload {
    param([hashtable] $Item, [string] $Directory)
    $path = Join-Path $Directory $Item.Name
    Write-Host "Lade $($Item.Name) ..."
    Invoke-WebRequest -Uri $Item.Url -OutFile $path -UseBasicParsing
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($hash -ne $Item.Sha256) { throw "SHA256 von $($Item.Name) stimmt nicht: $hash" }
    if ($Item.Signed) {
        $sig = Get-AuthenticodeSignature -LiteralPath $path
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
            throw "Signatur von $($Item.Name) ungültig: $($sig.Status) $($sig.SignerCertificate.Subject)"
        }
    }
    $path
}

if ($Phase -eq 'Setup') {
    if ($env:USERNAME -ne 'WDAGUtilityAccount') {
        throw 'Dieses Skript installiert und deinstalliert Programme. Nur in Windows Sandbox ausführen (Start-ActionSandbox.ps1).'
    }
    $work = Join-Path $env:TEMP 'si-setup'
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $files = @{}
    foreach ($d in $Downloads) { $files[$d.Name] = Get-VerifiedDownload -Item $d -Directory $work }

    Write-Host 'Installiere PowerShell 7 ...'
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$($files['PowerShell-7.6.8-win-x64.msi'])`" /qn /norestart" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "PowerShell-Installation fehlgeschlagen ($($p.ExitCode))" }

    Write-Host 'Installiere winget ...'
    $deps = Join-Path $work 'deps'
    Expand-Archive -LiteralPath $files['DesktopAppInstaller_Dependencies.zip'] -DestinationPath $deps -Force
    $appx = @(Get-ChildItem -LiteralPath $deps -Recurse -Filter '*.appx' | Where-Object { $_.FullName -match '\\x64\\' } | ForEach-Object FullName)
    Add-AppxPackage -Path $files['Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'] -DependencyPath $appx

    $pwsh = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Phase Test
    return
}

# ---------------- Phase „Test“ (PowerShell 7) ----------------

$results = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param([string] $Step, [bool] $Ok, [string] $Detail)
    $results.Add([pscustomobject] @{ Step = $Step; Ok = $Ok; Detail = $Detail })
    $color = if ($Ok) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} – {2}" -f $(if ($Ok) { 'OK ' } else { 'FEHLER' }), $Step, $Detail) -ForegroundColor $color
}
function Install-TestPackage {
    param([string[]] $Arguments)
    Write-Host "winget install $($Arguments -join ' ')"
    winget install @Arguments --silent --accept-source-agreements --accept-package-agreements --disable-interactivity | Out-Host
}
function Find-Program {
    param([scriptblock] $Filter)
    Get-SoftwareInventory -WarningAction SilentlyContinue | Where-Object $Filter | Select-Object -First 1
}

Install-PSResource -Name Microsoft.WinGet.Client -Version $WingetClientVersion -Scope CurrentUser -TrustRepository -AuthenticodeCheck
Import-Module C:\Repo\src\SoftwareInventory -Force
Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx | Out-Null

# 1. Aktualisieren über winget mit Adminrechten (7-Zip als MSI in alter Version)
Install-TestPackage @('--id', '7zip.7zip', '--exact', '--version', '24.08', '--installer-type', 'msi', '--scope', 'machine')
$sevenZip = Find-Program { $_.Name -like '7-Zip*' }
Add-Check '7-Zip installiert' ([bool] $sevenZip) "$($sevenZip.Name) $($sevenZip.Version), ProductCode $($sevenZip.ProductCode)"
if ($sevenZip) {
    $plan = $sevenZip | Update-Software -WhatIf
    Add-Check 'Update -WhatIf' ($plan.Result -eq 'Planned' -and $plan.Method -eq 'Winget' -and $plan.Elevated) $plan.CommandLine
    $r = $sevenZip | Update-Software -Confirm:$false
    Add-Check 'Update über winget (erhöht)' ($r.Result -in 'Succeeded', 'SucceededRebootRequired') "$($r.Result): $($r.VersionBefore) -> $($r.VersionAfter) $($r.Message)"

    # 2. Deinstallieren über MSI mit Wiederherstellungspunkt (in der Sandbox meist nicht verfügbar)
    $sevenZip = Find-Program { $_.Name -like '7-Zip*' }
    $r = $sevenZip | Uninstall-Software -Method Msi -CreateRestorePoint -Confirm:$false
    Add-Check 'Deinstallation über MSI' ($r.Result -eq 'Succeeded' -and $r.PresentAfter -eq $false) "$($r.Result) $($r.Message)"
    Add-Check 'Wiederherstellungspunkt gemeldet' ($r.RestorePoint -in 'Created', 'Skipped', 'NotAvailable', 'Failed' -and $r.RestorePointMessage) "$($r.RestorePoint): $($r.RestorePointMessage)"

    $again = $sevenZip | Uninstall-Software -Confirm:$false
    Add-Check 'Erneut deinstallieren -> NotInstalled' ($again.Result -eq 'NotInstalled') $again.Message
}

# 3. QuietUninstallString aus HKLM (Inno Setup)
Install-TestPackage @('--id', 'WinMerge.WinMerge', '--exact', '--scope', 'machine')
$winMerge = Find-Program { $_.Name -like 'WinMerge*' }
if ($winMerge) {
    $r = $winMerge | Uninstall-Software -Method QuietUninstallString -Confirm:$false
    Add-Check 'Deinstallation über QuietUninstallString' ($r.Result -eq 'Succeeded' -and $r.Elevated) "$($r.Result) $($r.CommandLine)"
}
else { Add-Check 'WinMerge installiert' $false 'nicht gefunden' }

# 4. Programm des Benutzers (HKCU) über winget ohne Adminrechte
Install-TestPackage @('--id', 'JanDeDobbeleer.OhMyPosh', '--exact', '--scope', 'user')
$userApp = Find-Program { $_.Name -like 'Oh My Posh*' }
if ($userApp) {
    $r = $userApp | Uninstall-Software -Confirm:$false
    Add-Check 'Deinstallation HKCU ohne Adminrechte' ($r.Result -eq 'Succeeded' -and -not $r.Elevated -and $r.Scope -eq 'User') "$($r.Result) $($r.Method) $($r.Message)"
}
else { Add-Check 'Oh My Posh installiert' $false 'nicht gefunden' }

# 5. Store-App (falls in der Sandbox vorhanden)
$app = Find-Program { $_.InstallType -eq 'MSIX' -and $_.PackageFullName -and $_.Name -notlike '*DesktopAppInstaller*' -and $_.Name -notlike '*App Installer*' }
if ($app) {
    $r = $app | Uninstall-Software -Method Appx -Confirm:$false
    Add-Check "Store-App entfernen ($($app.Name))" ($r.Result -eq 'Succeeded' -and -not $r.Elevated) "$($r.Result) $($r.Message)"
}
else { Write-Host 'Keine entfernbare Store-App in der Sandbox; Schritt übersprungen.' }

# 6. Protokoll
$log = @(Get-ActionLog)
Add-Check 'Protokoll lesbar' ($log.Count -ge 3) "$($log.Count) Aktionen protokolliert"
$log | Format-Table StartedAt, Action, Name, Method, Elevated, Result, RestorePoint -AutoSize | Out-Host

$file = Join-Path 'C:\Out' ("ergebnis-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[pscustomobject] @{ Checks = $results; ActionLog = $log } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $file -Encoding utf8NoBOM
$failed = @($results | Where-Object { -not $_.Ok }).Count
Write-Host ''
Write-Host "$($results.Count - $failed) von $($results.Count) Prüfungen bestanden. Ergebnis: $file" -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
