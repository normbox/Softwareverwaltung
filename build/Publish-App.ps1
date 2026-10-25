<#
.SYNOPSIS
    Veröffentlicht die App self-contained für Windows x64 (mit .NET-Laufzeit und PowerShell-Engine).
.DESCRIPTION
    Ergebnis liegt in artifacts\publish\Softwareverwaltung und als ZIP in artifacts\.
    Endbenutzer brauchen weder .NET noch PowerShell 7. Zum Bauen ist das .NET SDK 10 nötig.
    Bewusst kein Single-File: Die PowerShell-Module müssen als Dateien neben der App liegen.
.EXAMPLE
    .\build\Publish-App.ps1
#>
[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $repo 'src\Softwareverwaltung.App\Softwareverwaltung.App.csproj'
$artifacts = Join-Path $repo 'artifacts'
$output = Join-Path $artifacts 'publish\Softwareverwaltung'

if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }

dotnet publish $project -c $Configuration -r win-x64 --self-contained true -p:PublishSingleFile=false -o $output -nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet publish fehlgeschlagen ($LASTEXITCODE)." }

foreach ($required in 'Softwareverwaltung.exe', 'Modules\SoftwareInventory\SoftwareInventory.psd1', 'Modules\Microsoft.WinGet.Client') {
    if (-not (Test-Path -LiteralPath (Join-Path $output $required))) { throw "Im Ergebnis fehlt $required." }
}
Copy-Item -LiteralPath (Join-Path $repo 'LICENSE'), (Join-Path $repo 'THIRD-PARTY-NOTICES.md') -Destination $output

[xml] $csproj = Get-Content -LiteralPath $project -Raw
$version = $csproj.Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
$zip = Join-Path $artifacts "Softwareverwaltung-$version-win-x64.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $zip -CompressionLevel Optimal

$size = (Get-ChildItem -LiteralPath $output -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("Fertig: {0} ({1:N0} MB entpackt, ZIP {2:N0} MB)" -f $output, $size, ((Get-Item $zip).Length / 1MB))
