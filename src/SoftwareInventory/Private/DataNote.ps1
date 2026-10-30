# Protokoll für Auffälligkeiten in Fremddaten (z. B. Commit-Kennung statt Version in einem CVE-Datensatz):
# %LOCALAPPDATA%\SoftwareInventory\logs\data-notes\<yyyy-MM-dd>.jsonl (Datum in UTC), eine JSON-Zeile je Fall.
# Dient dem späteren Auffinden solcher Fälle; räumt sich mit der Selbstbereinigung von logs\ auf.
# Je Lauf wird derselbe Fall nur einmal geschrieben.

$script:DataNotesSeen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Get-DataNoteDirectory {
    Join-Path (Get-AppDataDirectory) 'logs\data-notes'
}

function Write-DataNote {
    <#
    .SYNOPSIS
        Vermerkt eine Auffälligkeit in Fremddaten mit festem Code.
    .DESCRIPTION
        Fehler beim Schreiben werden nur ausführlich gemeldet; die Prüfung läuft weiter.
    #>
    param(
        [Parameter(Mandatory)] [string] $Code,
        [Parameter(Mandatory)] [string] $Source,
        [string] $CveId,
        [string] $Product,
        [string[]] $Value = @()
    )
    $key = "$Code|$Source|$CveId|$Product|$($Value -join ',')"
    if (-not $script:DataNotesSeen.Add($key)) { return }
    $now = [datetime]::UtcNow
    $entry = [ordered]@{
        Timestamp = $now.ToString('o')
        Code      = $Code
        Source    = $Source
        CveId     = $CveId
        Product   = $Product
        Value     = @($Value)
        Text      = Get-LocalizedString "DataNote$Code" ($Value -join ', '), $CveId
    }
    try {
        $directory = Get-DataNoteDirectory
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $line = $entry | ConvertTo-Json -Compress -Depth 4
        [System.IO.File]::AppendAllText((Join-Path $directory ($now.ToString('yyyy-MM-dd') + '.jsonl')), $line + "`n", [System.Text.UTF8Encoding]::new($false))
    }
    catch { Write-Verbose "Hinweis nicht schreibbar: $($_.Exception.Message)" }
}
