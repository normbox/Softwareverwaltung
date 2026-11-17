BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

    # Zeichen, die in Quelldateien nie roh stehen dürfen. Sie gehören als Escape geschrieben: in PowerShell [char]0x1F,
    # in C# und JSON ein Backslash-u mit vier Hexziffern, in XAML und resx &#x1F;.
    # Die Bereiche stehen als Dezimal-Codepunkte in tests/Data/unsafe-chars.json (gemeinsam mit dem Hook
    # .claude/hooks/check-control-chars.ps1, dort auch die Erklärung der Bereiche). Die Zeichenklasse wird hier aus
    # Codepunkten gebaut und nicht als Text mit Backslash-u-Escapes hingeschrieben: Ein Werkzeug, das solche Escapes
    # beim Schreiben auflöst, würde die rohen Zeichen sonst in diese Datei setzen.
    $script:UnsafeTable = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'tests\Data\unsafe-chars.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $class = -join ($script:UnsafeTable.ranges | ForEach-Object {
            if ($_[0] -eq $_[1]) { '\u{0:X4}' -f $_[0] } else { '\u{0:X4}-\u{1:X4}' -f $_[0], $_[1] }
        })
    $script:ControlPattern = [regex]::new('[' + $class + ']')
    $script:StrictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

    function Find-RawControlCharacter {
        # Liefert je Fund Datei, Zeile und Zeichencode (höchstens fünf je Datei). Die Datei muss gültiges UTF-8 sein
        # (mit oder ohne BOM): Eine andere Kodierung (z. B. CP1252 von einer Shell) ist selbst ein Fund.
        param([string] $Path)
        try { $bytes = [System.IO.File]::ReadAllBytes($Path) }
        catch { return [pscustomobject] @{ Path = $Path; Line = 0; Code = 'nicht lesbar' } }
        $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
        try { $text = $script:StrictUtf8.GetString($bytes, $offset, $bytes.Length - $offset) }
        catch { return [pscustomobject] @{ Path = $Path; Line = 0; Code = 'kein gültiges UTF-8' } }
        foreach ($match in $script:ControlPattern.Matches($text) | Select-Object -First 5) {
            # Zeilenumbrüche CRLF, CR und LF zählen, nicht nur LF.
            $line = 1 + [regex]::Matches($text.Substring(0, $match.Index), "\r\n|\r|\n").Count
            [pscustomobject] @{ Path = $Path; Line = $line; Code = 'U+{0:X4}' -f [int] $match.Value[0] }
        }
    }

    function Get-SourceFile {
        # Die Dateiliste kommt von git (verfolgte und neue, nicht ignorierte Dateien): Build-Ausgaben, Arbeitskopien und
        # lokale Dateien sind damit ausgeschlossen, ohne dass ein Ordnername etwas verdeckt. Ohne git scheitert der Test.
        $git = Get-Command git -ErrorAction SilentlyContinue
        if (-not $git) { throw 'git wurde nicht gefunden: Die Dateiliste kommt aus git ls-files.' }
        $listing = & $git.Source -C $script:RepoRoot ls-files -z --cached --others --exclude-standard
        if ($LASTEXITCODE -ne 0) { throw 'git ls-files ist fehlgeschlagen.' }
        $extensions = @($script:UnsafeTable.sourceExtensions)
        foreach ($relative in ($listing -join '').Split([char] 0, [System.StringSplitOptions]::RemoveEmptyEntries)) {
            if ($extensions -notcontains [System.IO.Path]::GetExtension($relative).ToLowerInvariant()) { continue }
            $full = Join-Path $script:RepoRoot $relative
            # Eine verfolgte, aber gelöschte Datei (noch nicht committet) gibt es nicht mehr.
            if (Test-Path -LiteralPath $full -PathType Leaf) { $full }
        }
    }
}

Describe 'Quelldateien ohne rohe Steuerzeichen' {
    It 'erkennt rohe Steuerzeichen, Trennzeichen, Bidi- und Zero-Width-Zeichen und lässt Tab, CR, LF und die BOM am Anfang zu' {
        $file = Join-Path $TestDrive 'probe.ps1'
        [System.IO.File]::WriteAllText($file, "a`tb`r`nc`n")
        @(Find-RawControlCharacter $file) | Should -BeNullOrEmpty
        [System.IO.File]::WriteAllText($file, "a`r`n", [System.Text.UTF8Encoding]::new($true))
        @(Find-RawControlCharacter $file) | Should -BeNullOrEmpty -Because 'eine BOM am Dateianfang ist erlaubt'

        foreach ($code in 0x00, 0x01, 0x08, 0x0B, 0x0C, 0x0E, 0x1B, 0x1F, 0x7F, 0x80, 0x85, 0x9F, 0x200B, 0x200C, 0x200D,
            0x2028, 0x2029, 0x202A, 0x202E, 0x2060, 0x2066, 0x2069, 0xFEFF) {
            [System.IO.File]::WriteAllText($file, "x`ny" + [char] $code + "z`n")
            $hit = @(Find-RawControlCharacter $file)
            $hit.Count | Should -Be 1 -Because ('U+{0:X4} muss gefunden werden' -f $code)
            $hit[0].Line | Should -Be 2
            $hit[0].Code | Should -Be ('U+{0:X4}' -f $code)
        }
    }

    It 'lässt häufige erlaubte Zeichen zu (Umlaute, typografische Striche und Anführungszeichen, Pfeile, NBSP, Soft Hyphen)' {
        $file = Join-Path $TestDrive 'allowed.ps1'
        # Codepunkte statt roher Zeichen: ä ö ü ß, En- und Em-Dash, typografische Anführungszeichen, Pfeil, NBSP, Soft Hyphen
        $text = -join ([char[]] @(0xE4, 0xF6, 0xFC, 0xDF, 0x2013, 0x2014, 0x201E, 0x201C, 0x2192, 0xA0, 0xAD))
        [System.IO.File]::WriteAllText($file, "# $text`n")
        @(Find-RawControlCharacter $file) | Should -BeNullOrEmpty
    }

    It 'zählt die Zeile bei CRLF, CR und LF' {
        $file = Join-Path $TestDrive 'lines.ps1'
        foreach ($newline in "`r`n", "`r", "`n") {
            [System.IO.File]::WriteAllText($file, "a$($newline)b$($newline)c" + [char] 1)
            (Find-RawControlCharacter $file).Line | Should -Be 3
        }
    }

    It 'meldet eine Datei, die kein gültiges UTF-8 ist (UTF-16 mit BOM, CP1252-Umlaut)' {
        $file = Join-Path $TestDrive 'encoding.ps1'
        [System.IO.File]::WriteAllText($file, 'abc', [System.Text.Encoding]::Unicode)
        (Find-RawControlCharacter $file).Code | Should -Be 'kein gültiges UTF-8'
        [System.IO.File]::WriteAllBytes($file, [byte[]] @(0x61, 0xE4, 0x62))
        (Find-RawControlCharacter $file).Code | Should -Be 'kein gültiges UTF-8'
    }

    It 'meldet eine Datei, die sich nicht lesen lässt' {
        (Find-RawControlCharacter (Join-Path $TestDrive 'gibt-es-nicht.ps1')).Code | Should -Be 'nicht lesbar'
    }

    It 'findet in der Repository-Struktur Quelldateien (Prüfung läuft nicht ins Leere)' {
        $files = @(Get-SourceFile)
        $files.Count | Should -BeGreaterThan 100
        $extensions = $files | ForEach-Object { [System.IO.Path]::GetExtension($_).ToLowerInvariant() } | Sort-Object -Unique
        $extensions | Should -Contain '.ps1'
        $extensions | Should -Contain '.cs'
        $extensions | Should -Contain '.json'
        $extensions | Should -Contain '.manifest'
    }

    It 'enthält keine Quelldatei rohe Steuerzeichen oder ungültiges UTF-8' {
        $problems = foreach ($file in Get-SourceFile) {
            foreach ($hit in Find-RawControlCharacter $file) {
                '{0}:{1} {2}' -f $hit.Path.Substring($script:RepoRoot.Length + 1), $hit.Line, $hit.Code
            }
        }
        $problems | Should -BeNullOrEmpty -Because ("rohe Steuerzeichen als Escape schreiben ([char]0x1F in PowerShell):`n" + (@($problems) -join "`n"))
    }
}
