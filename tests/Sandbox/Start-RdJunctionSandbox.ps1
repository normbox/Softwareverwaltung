<#
.SYNOPSIS
    Startet die Prüfung „rd /s folgt keinen Junctions“ (Admin-Teil von Remove-AppData) in Windows Sandbox.
.DESCRIPTION
    Erzeugt eine .wsb-Datei mit den Pfaden dieses Repositorys und startet Windows Sandbox ohne Netzwerk. Das Repository
    wird schreibgeschützt eingebunden; das Ergebnis landet in tests\Sandbox\out (rd-junction-<Zeit>.txt). In der Sandbox
    läuft Test-RdJunction.ps1 automatisch in einem sichtbaren Konsolenfenster an. Auf dem eigenen Rechner wird nichts
    verändert. Voraussetzung: Windows 10/11 Pro oder Enterprise mit aktivierter Funktion „Windows-Sandbox“.
.EXAMPLE
    .\tests\Sandbox\Start-RdJunctionSandbox.ps1
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
  <Networking>Disable</Networking>
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
    <Command>explorer.exe C:\Repo\tests\Sandbox\Start-RdJunctionInSandbox.cmd</Command>
  </LogonCommand>
</Configuration>
"@

$path = Join-Path ([System.IO.Path]::GetTempPath()) 'SoftwareInventory-RdJunction.wsb'
Set-Content -LiteralPath $path -Value $wsb -Encoding UTF8
Write-Host "Starte Windows Sandbox ($path). Ergebnis: $out"
Start-Process -FilePath $sandbox -ArgumentList "`"$path`""
