# Vom Benutzer bestätigte CPE-Zuordnungen für Programme ohne Katalogeintrag.
# Gespeichert unter %APPDATA%\SoftwareInventory\cpe-map.json, je Programm ein Schlüssel.

function Get-CpeMappingPath {
    Join-Path $env:APPDATA 'SoftwareInventory\cpe-map.json'
}

function Get-CpeMappingKey {
    # Stabiler Schlüssel: winget-ID, sonst Name + Herstellerschlüssel (ohne Version im Namen).
    param([Parameter(Mandatory)] $Record)
    if ($Record.WingetId) { return "winget:$($Record.WingetId)".ToLowerInvariant() }
    $name = ($Record.Name -replace '\s+v?\d+(\.\d+)+.*$', '').Trim()
    "name:$name|$(Get-PublisherKey $Record.Publisher)".ToLowerInvariant()
}

function Read-CpeMapping {
    # Hashtabelle Schlüssel -> @{ Key; Name; Cpe; ConfirmedAt }; unlesbare Datei = leer mit Warnung.
    $path = Get-CpeMappingPath
    $map = @{}
    if (-not (Test-Path -LiteralPath $path)) { return $map }
    try {
        foreach ($entry in @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String)) {
            if ($entry -and $entry.Key -and $entry.Cpe) { $map[$entry.Key] = $entry }
        }
    }
    catch { Write-Warning (Get-LocalizedString 'WarningCpeMappingUnreadable' $path, $_.Exception.Message) }
    $map
}

function Write-CpeMapping {
    param([hashtable] $Map)
    $path = Get-CpeMappingPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    ConvertTo-Json -InputObject @($Map.Values | Sort-Object Key) -Depth 4 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
}

function Get-RecordCpe {
    <#
    .SYNOPSIS
        CPE-Namen (ohne Version) eines Datensatzes: Katalog vor bestätigter Benutzerzuordnung.
    #>
    param([Parameter(Mandatory)] $Record, $CatalogEntry, [hashtable] $UserMap)
    $fromCatalog = @(if ($CatalogEntry) { Get-CatalogValue $CatalogEntry 'Cpe' }) | Where-Object { $_ }
    if ($fromCatalog) { return [pscustomobject] @{ Cpe = [string[]] $fromCatalog; Source = 'Catalog' } }
    if ($UserMap) {
        $mapped = $UserMap[(Get-CpeMappingKey $Record)]
        if ($mapped) { return [pscustomobject] @{ Cpe = [string[]] @($mapped.Cpe); Source = 'User' } }
    }
    $null
}
