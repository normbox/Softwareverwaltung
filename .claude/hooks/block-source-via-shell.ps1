# PreToolUse (Bash, PowerShell): blockiert Befehle, die eine Quelldatei über die Shell schreiben.
# Regel aus CLAUDE.md: Quelltext nie über Shell-Quoting erzeugen oder ändern (kein Heredoc, sed, echo, Set-Content ...).
# Geprüft wird nur, wenn das Ziel eine Quelldatei-Endung hat (Tabelle tests/Data/unsafe-chars.json). Ziele in Temp und im
# Scratchpad sind erlaubt (Hilfsskripte). Das ist eine Leitplanke, keine Garantie: Shell-Befehle lassen sich nicht sauber parsen.
. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    $data = Read-HookInput
    $command = [string] $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

    $extensions = (Get-UnsafeTable).sourceExtensions | ForEach-Object { [regex]::Escape($_.TrimStart('.')) }
    $extPattern = '(?:' + ($extensions -join '|') + ')'
    # Ein Pfad-Token mit Quelldatei-Endung (ohne Leerzeichen, Anführungszeichen, Pipe, Semikolon).
    $tokenPattern = '[^\s"''|;&<>()]*\.' + $extPattern + '(?=$|[\s"''|;&<>()])'
    $tempPattern = '(?i)[\\/](?:temp|tmp|scratchpad)[\\/]'

    $isSource = { param($token) $token -notmatch $tempPattern }
    $sourceTokens = @([regex]::Matches($command, $tokenPattern) | ForEach-Object { $_.Value } | Where-Object { & $isSource $_ })
    if ($sourceTokens.Count -eq 0) { exit 0 }

    $reason = $null
    # Umleitung direkt auf eine Quelldatei (> oder >>, auch 1>), nicht 2>&1
    foreach ($m in [regex]::Matches($command, '(?<![<>&\d])\d?>>?\s*["'']?(' + $tokenPattern.Replace('(?=$|[\s"''|;&<>()])', '') + ')')) {
        if (& $isSource $m.Groups[1].Value) { $reason = "Umleitung nach $($m.Groups[1].Value)"; break }
    }
    if (-not $reason -and $command -match '(?i)\btee\b') { $reason = 'tee' }
    if (-not $reason -and $command -match '(?i)\bsed\b[^|;\r\n]*\s-[a-z]*i') { $reason = 'sed -i' }
    if (-not $reason -and $command -match '(?i)\b(?:Set-Content|Add-Content|Out-File|Clear-Content)\b') { $reason = 'Set-Content/Add-Content/Out-File' }
    if (-not $reason -and $command -match '(?i)\.(?:WriteAll(?:Text|Lines|Bytes)|AppendAll(?:Text|Lines)|Write(?:Text|Bytes)?)\s*\(|write_text|write_bytes|\bopen\s*\(') { $reason = 'Schreibaufruf (WriteAllText, open(...).write ...)' }

    if ($reason) {
        Stop-HookWithBlock ("Blockiert ($reason): Quelldateien nie über die Shell ändern (CLAUDE.md, Abschnitt Zusammenarbeit). " +
            "Einzelne Änderungen mit Edit oder Write; für viele Ersetzungen ein Hilfsskript mit Write im Scratchpad anlegen und ausführen. " +
            "Betroffen: " + ($sourceTokens -join ', '))
    }
    exit 0
}
catch { exit 0 }
