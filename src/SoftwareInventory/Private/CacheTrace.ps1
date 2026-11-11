# Zwischenspeicher je Programm: Mitschrieb der benutzten Einträge (für „geprüft vor …“ und „veraltet“),
# Neu prüfen ohne Cache und ein Index je Programm und Version, über den sich die Einträge eines
# Programms gezielt verwerfen lassen (Clear-CheckCache, z. B. nach einer Aktion).

# Sammellauf für den Index (Get-SecurityRating): Pfad → @{ Update; Vulnerability }, $null außerhalb.
$script:CheckIndexBatch = $null

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
    # Vermerkt einen benutzten Eintrag für das gerade geprüfte Programm. -Failure: Der Dienst antwortete
    # nicht, der Eintrag ist ein Rückfall auf alte Daten (Meldung mit Grund, für ServiceProblems).
    param([string] $Service, [string] $File, [datetime] $FetchedAt, [timespan] $MaxAge, $Failure)
    if ($null -eq $script:CheckTrace) { return }
    $script:CheckTrace.Add([pscustomobject] @{
            Service   = $Service
            File      = $File
            FetchedAt = $FetchedAt
            Stale     = ([datetime]::UtcNow - $FetchedAt) -gt $MaxAge
            Failure   = $Failure
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
    <#
    .SYNOPSIS
        Vermerkt, welche Einträge die Versions- bzw. Sicherheitsprüfung (Kind) eines Programms benutzt hat.
    .DESCRIPTION
        Während eines Sammellaufs (Enter-CheckIndexBatch, z. B. in Get-SecurityRating) nur im Speicher;
        geschrieben wird am Ende einmal je Programm. Sonst sofort. Geschrieben wird nur, wenn sich der Inhalt
        ändert: Viele unveränderte Neuschreibungen in kurzer Folge lösen Verhaltensschutz-Programme aus.
    #>
    param($Record, [ValidateSet('Update', 'Vulnerability')] [string] $Kind, [object[]] $Trace)
    # KEV und EPSS gelten für alle Programme und werden nie gezielt verworfen; sie gehören nicht in den Index.
    $files = @($Trace | Where-Object { $_ -and $_.File -and $_.Service -notin 'KEV', 'EPSS' } | ForEach-Object File | Sort-Object -Unique)
    if (-not $files) { return }
    $path = Get-CheckIndexFile $Record
    if ($null -ne $script:CheckIndexBatch) {
        if (-not $script:CheckIndexBatch.Contains($path)) { $script:CheckIndexBatch[$path] = @{} }
        $script:CheckIndexBatch[$path][$Kind] = $files
        return
    }
    Write-CheckIndex -Path $path -Change @{ $Kind = $files }
}

function Enter-CheckIndexBatch {
    # Startet einen Sammellauf; liefert $true, wenn dieser Aufruf ihn begonnen hat (und beenden muss).
    if ($null -ne $script:CheckIndexBatch) { return $false }
    $script:CheckIndexBatch = [ordered]@{}
    $true
}

function Exit-CheckIndexBatch {
    # Beendet den Sammellauf und schreibt je Programm einmal (auch nach Abbruch, für das bis dahin Geprüfte).
    param([bool] $Owner)
    if (-not $Owner) { return }
    $batch = $script:CheckIndexBatch
    $script:CheckIndexBatch = $null
    foreach ($path in $batch.Keys) { Write-CheckIndex -Path $path -Change $batch[$path] }
}

function Write-CheckIndex {
    # Übernimmt die geänderten Teile (Update/Vulnerability) in den Index und schreibt nur bei geändertem Inhalt.
    param([string] $Path, [hashtable] $Change)
    try {
        $index = [ordered]@{ Update = @(); Vulnerability = @() }
        $oldText = if (Test-Path -LiteralPath $Path) { (Get-Content -LiteralPath $Path -Raw).Trim() }
        if ($oldText) {
            try {
                $old = $oldText | ConvertFrom-Json
                foreach ($k in 'Update', 'Vulnerability') { if ($old.PSObject.Properties[$k]) { $index[$k] = @($old.$k) } }
            }
            catch { Write-Verbose "Index unlesbar, wird neu geschrieben: $Path" }
        }
        foreach ($k in $Change.Keys) { $index[$k] = @($Change[$k]) }
        $text = [pscustomobject] $index | ConvertTo-Json -Compress
        if ($text -ceq $oldText) { return }
        Write-CheckIndexFile -Path $Path -Text $text
    }
    catch { Write-Verbose "Index nicht schreibbar: $Path ($($_.Exception.Message))" }
}

function Write-CheckIndexFile {
    # Eigene Funktion, damit Tests die Schreibvorgänge zählen können.
    param([string] $Path, [string] $Text)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}
