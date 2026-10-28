# Zwischenspeicher je Programm: Mitschrieb der benutzten Einträge (für „geprüft vor …“ und „veraltet“),
# Neu prüfen ohne Cache und ein Index je Programm und Version, über den sich die Einträge eines
# Programms gezielt verwerfen lassen (Clear-CheckCache, z. B. nach einer Aktion).

function Test-CacheRefresh {
    # Wahr, wenn diese Datei im laufenden Neu-prüfen-Lauf noch nicht frisch geholt wurde (merkt sie sich dabei).
    param([string] $File)
    $null -ne $script:CacheRefresh -and $script:CacheRefresh.Add($File)
}

function Enter-CacheRefresh {
    # Startet einen Lauf ohne Cache; liefert $true, wenn dieser Aufruf ihn begonnen hat (und beenden muss).
    if ($null -ne $script:CacheRefresh) { return $false }
    $script:CacheRefresh = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $true
}

function Exit-CacheRefresh {
    param([bool] $Owner)
    if ($Owner) { $script:CacheRefresh = $null }
}

function Add-CheckTrace {
    # Vermerkt einen benutzten Eintrag für das gerade geprüfte Programm.
    param([string] $Service, [string] $File, [datetime] $FetchedAt, [timespan] $MaxAge)
    if ($null -eq $script:CheckTrace) { return }
    $script:CheckTrace.Add([pscustomobject] @{
            Service   = $Service
            File      = $File
            FetchedAt = $FetchedAt
            Stale     = ([datetime]::UtcNow - $FetchedAt) -gt $MaxAge
        })
}

function Invoke-WithCheckTrace {
    # Führt $ScriptBlock mit eigenem Mitschrieb aus; liefert @{ Output; Trace }.
    param([scriptblock] $ScriptBlock)
    $outer = $script:CheckTrace
    $script:CheckTrace = [System.Collections.Generic.List[object]]::new()
    try {
        $output = & $ScriptBlock
        @{ Output = $output; Trace = @($script:CheckTrace) }
    }
    finally { $script:CheckTrace = $outer }
}

function Get-CheckTraceSummary {
    # Ältester Abruf und ob ein Eintrag älter als seine Haltbarkeit ist.
    param([object[]] $Trace)
    $entries = @($Trace | Where-Object { $_ })
    if (-not $entries) { return @{ CheckedAt = $null; Stale = $false } }
    @{
        CheckedAt = ($entries | Sort-Object FetchedAt | Select-Object -First 1).FetchedAt
        Stale     = [bool] ($entries | Where-Object Stale)
    }
}

function Get-CheckIndexFile {
    # Index je Programm und Version: Hash ohne Namen und Pfade.
    param($Record)
    $key = "$(Get-RecordIdentity $Record)|$($Record.Version)"
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($key)))
    Join-Path (Join-Path (Get-CacheDirectory) 'index') "$hash.json"
}

function Save-CheckIndex {
    # Vermerkt, welche Einträge die Versions- bzw. Sicherheitsprüfung (Kind) eines Programms benutzt hat.
    param($Record, [ValidateSet('Update', 'Vulnerability')] [string] $Kind, [object[]] $Trace)
    # Der KEV-Katalog gilt für alle Programme und wird nie gezielt verworfen; er gehört nicht in den Index.
    $files = @($Trace | Where-Object { $_ -and $_.File -and $_.Service -ne 'KEV' } | ForEach-Object File | Sort-Object -Unique)
    if (-not $files) { return }
    $path = Get-CheckIndexFile $Record
    $index = [ordered]@{ Update = @(); Vulnerability = @() }
    try {
        if (Test-Path -LiteralPath $path) {
            $old = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            foreach ($k in 'Update', 'Vulnerability') { if ($old.PSObject.Properties[$k]) { $index[$k] = @($old.$k) } }
        }
        $index[$Kind] = $files
        New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
        [pscustomobject] $index | ConvertTo-Json -Compress | Set-Content -LiteralPath $path -Encoding utf8NoBOM
    }
    catch { Write-Verbose "Index nicht schreibbar: $path ($($_.Exception.Message))" }
}
