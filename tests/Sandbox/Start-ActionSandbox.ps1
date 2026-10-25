<#
.SYNOPSIS
    Startet den Integrationstest für Aktualisieren/Deinstallieren in Windows Sandbox.
.DESCRIPTION
    Erzeugt eine .wsb-Datei mit den Pfaden dieses Repositorys und startet Windows Sandbox.
    Das Repository wird schreibgeschützt eingebunden; Ergebnisse landen in tests\Sandbox\out.
    In der Sandbox läuft Invoke-ActionSandboxTest.ps1 automatisch an.
    Voraussetzung: Windows 10/11 Pro oder Enterprise mit aktivierter Funktion „Windows-Sandbox“.
    Auf dem eigenen Rechner wird nichts installiert oder deinstalliert.
.EXAMPLE
    .\tests\Sandbox\Start-ActionSandbox.ps1
#>
[CmdletBinding()]
param()

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = Join-Path $PSScriptRoot 'out'
New-Item -ItemType Directory -Path $out -Force | Out-Null

$sandbox = Join-Path $env:windir 'System32\WindowsSandbox.exe'
if (-not (Test-Path -LiteralPath $sandbox)) {
    throw 'Windows Sandbox ist nicht aktiviert (Windows-Features: „Windows-Sandbox“).'
}

$wsb = @"
<Configuration>
  <Networking>Enable</Networking>
  <MemoryInMB>6144</MemoryInMB>
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
    <Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File C:\Repo\tests\Sandbox\Invoke-ActionSandboxTest.ps1</Command>
  </LogonCommand>
</Configuration>
"@

$path = Join-Path ([System.IO.Path]::GetTempPath()) 'SoftwareInventory-Aktionen.wsb'
Set-Content -LiteralPath $path -Value $wsb -Encoding UTF8
Write-Host "Starte Windows Sandbox ($path). Ergebnisse: $out"
Start-Process -FilePath $sandbox -ArgumentList "`"$path`""
