# PostToolUse (Edit, Write): prüft die geänderte Datei sofort auf rohe Steuerzeichen, Zeilentrenner, Bidi- und
# Zero-Width-Zeichen und ungültiges UTF-8 (Regel aus CLAUDE.md; derselbe Befund wie tests/Unit/SourceFiles.Tests.ps1).
# Die Bereiche und Endungen kommen aus tests/Data/unsafe-chars.json (Dezimal-Codepunkte, gemeinsame Tabelle).
# Erlaubt sind Tab, CR, LF und eine BOM am Dateianfang. Nur Dateien im Repository, nicht in .claude\worktrees, obj, bin.
. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    $data = Read-HookInput
    $path = [string] $data.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { exit 0 }
    $full = (Resolve-Path -LiteralPath $path).Path

    $root = Get-HookRepoRoot
    if (-not $full.StartsWith($root + '\', [System.StringComparison]::OrdinalIgnoreCase)) { exit 0 }
    $relative = $full.Substring($root.Length + 1)
    if ($relative -match '(?i)^\.claude\\worktrees\\|(^|\\)(obj|bin|node_modules)\\') { exit 0 }

    $table = Get-UnsafeTable
    if (@($table.sourceExtensions) -notcontains [System.IO.Path]::GetExtension($full).ToLowerInvariant()) { exit 0 }

    $class = -join ($table.ranges | ForEach-Object {
            if ($_[0] -eq $_[1]) { '\u{0:X4}' -f $_[0] } else { '\u{0:X4}-\u{1:X4}' -f $_[0], $_[1] }
        })
    $pattern = [regex]::new('[' + $class + ']')

    $bytes = [System.IO.File]::ReadAllBytes($full)
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    try { $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes, $offset, $bytes.Length - $offset) }
    catch { Stop-HookWithBlock "Befund in ${relative}: kein gültiges UTF-8. Datei als UTF-8 schreiben (Edit/Write, nicht über die Shell)." }

    $found = @($pattern.Matches($text) | Select-Object -First 5 | ForEach-Object {
            $line = 1 + [regex]::Matches($text.Substring(0, $_.Index), "\r\n|\r|\n").Count
            'Zeile {0}: U+{1:X4}' -f $line, [int] $_.Value[0]
        })
    if ($found.Count -gt 0) {
        Stop-HookWithBlock ("Befund in ${relative}: rohe Steuerzeichen (" + ($found -join '; ') + "). Unsichtbare Zeichen nie als Escape-Text schreiben: " +
            "in PowerShell [char]0x1F, in C# (char)0x1F, in XAML und resx &#x1F;, in Testdaten {U+XXXX} (CLAUDE.md). Stelle sofort korrigieren.")
    }
    exit 0
}
catch { exit 0 }
