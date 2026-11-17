# Gemeinsame Hilfen der Claude-Code-Hooks (siehe CLAUDE.md, Abschnitt "Hooks").
# Regeln für alle Hooks:
#  - Eingabe ist das JSON von Claude Code auf stdin.
#  - Exit 2 blockiert den Aufruf, die Meldung auf stderr geht an Claude. Exit 0 lässt durch.
#  - Fail-open: Lässt sich die Eingabe nicht lesen oder wirft ein Hook, blockiert er nie (Exit 0 bzw. 1).

function Read-HookInput {
    # Liest stdin als UTF-8 und liefert das Objekt, bei Fehlern $null.
    try {
        $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), [System.Text.UTF8Encoding]::new($false))
        $raw = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return $raw | ConvertFrom-Json
    }
    catch { return $null }
}

function Stop-HookWithBlock {
    # Blockiert den Aufruf: Meldung auf stderr, Exit 2.
    param([Parameter(Mandatory)] [string] $Message)
    [Console]::Error.WriteLine($Message)
    exit 2
}

function Write-HookNote {
    # Hinweis ohne zu blockieren (Exit 0). additionalContext erreicht Claude, stderr erscheint im ausführlichen Modus.
    param([Parameter(Mandatory)] [string] $Message)
    [Console]::Error.WriteLine($Message)
    $payload = @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; additionalContext = $Message } }
    [Console]::Out.WriteLine(($payload | ConvertTo-Json -Compress -Depth 4))
}

function Get-HookRepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-UnsafeTable {
    # Gemeinsame Tabelle mit tests/Unit/SourceFiles.Tests.ps1: Bereiche (Dezimal-Codepunkte) und Quelldatei-Endungen.
    $path = Join-Path (Get-HookRepoRoot) 'tests\Data\unsafe-chars.json'
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Split-ShellSegment {
    # Zerlegt eine Befehlszeile grob in Teilbefehle (an ; && || | und Zeilenumbrüchen). Keine echte Shell-Analyse:
    # Anführungszeichen werden nicht beachtet, das ist für Leitplanken genug.
    param([Parameter(Mandatory)] [string] $Command)
    $Command -split '(?:&&|\|\||[;|\r\n])' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
}

function Get-CommandWord {
    # Erstes Wort eines Teilbefehls ohne führendes "& " / ". ", Anführungszeichen, Pfad und .exe, kleingeschrieben.
    param([Parameter(Mandatory)] [string] $Segment)
    $text = $Segment -replace '^[&.]\s+', ''
    if ($text -match '^\s*(?:"([^"]*)"|''([^'']*)''|(\S+))') {
        $word = ($Matches[1], $Matches[2], $Matches[3] | Where-Object { $_ } | Select-Object -First 1)
        $leaf = $word -replace '^.*[\\/]', ''
        return ($leaf -replace '\.exe$', '').ToLowerInvariant()
    }
    return ''
}
