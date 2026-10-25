<#
.SYNOPSIS
    Prüft die veröffentlichte App in Windows Sandbox: ohne .NET, ohne PowerShell 7, ohne winget.
.DESCRIPTION
    Vorher .\build\Publish-App.ps1 ausführen. Die Sandbox startet die App zweimal (ohne und mit
    aktivierten Quellen), macht Bildschirmfotos und schreibt das Ergebnis nach tests\Sandbox\out.
    In der Sandbox öffnet sich ein Konsolenfenster; eingreifen ist nicht nötig. Es darf nur eine
    Sandbox gleichzeitig laufen.
.EXAMPLE
    .\tests\Sandbox\Start-AppSandbox.ps1
#>
[CmdletBinding()]
param()

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $repo 'artifacts\publish\Softwareverwaltung\Softwareverwaltung.exe'))) {
    throw 'Veröffentlichte App fehlt. Zuerst .\build\Publish-App.ps1 ausführen.'
}
$sandbox = Join-Path $env:windir 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandbox)) {
    throw 'Windows Sandbox ist nicht aktiviert (Windows-Features: „Windows-Sandbox“).'
}
if (Get-Process -Name WindowsSandboxRemoteSession, WindowsSandboxClient -ErrorAction SilentlyContinue) {
    throw 'Es läuft bereits eine Sandbox. Bitte zuerst schließen.'
}

$wsb = @"
<Configuration>
  <Networking>Disable</Networking>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$([System.Security.SecurityElement]::Escape($repo))</HostFolder>
      <SandboxFolder>C:\Repo</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$([System.Security.SecurityElement]::Escape($out))</HostFolder>
      <SandboxFolder>C:\Out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>explorer.exe C:\Repo\tests\Sandbox\Start-AppInSandbox.cmd</Command>
  </LogonCommand>
</Configuration>
"@

$path = Join-Path ([System.IO.Path]::GetTempPath()) 'Softwareverwaltung-App.wsb'
Set-Content -LiteralPath $path -Value $wsb -Encoding UTF8
Write-Host "Starte Windows Sandbox ($path). Ergebnisse: $out"
Start-Process -FilePath $sandbox -ArgumentList "`"$path`""
