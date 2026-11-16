BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

    # Rohe Steuerzeichen in Quelldateien: U+0000-U+0008, U+000B, U+000C, U+000E-U+001F, U+007F und die C1-Zeichen
    # U+0080-U+009F. Erlaubt sind nur Tab, CR und LF. Steuerzeichen gehören im Code als Escape geschrieben
    # ([char]0x1F, "\u001F"), nie roh; die Shell hat so etwas schon einmal still in eine Datei geschrieben.
    # Das Muster steht hier absichtlich als Escape, damit diese Datei selbst sauber bleibt.
    $script:ControlPattern = [regex]::new('[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]')

    function Find-RawControlCharacter {
        # Liefert je Fund Datei, Zeile und Zeichencode (nur die ersten fünf je Datei).
        param([string] $Path)
        $text = [System.IO.File]::ReadAllText($Path)
        $found = $script:ControlPattern.Matches($text)
        foreach ($match in $found | Select-Object -First 5) {
            $line = 1 + ($text.Substring(0, $match.Index).Split("`n").Count - 1)
            [pscustomobject] @{ Path = $Path; Line = $line; Code = 'U+{0:X4}' -f [int] $match.Value[0] }
        }
    }

    function Get-SourceFile {
        $extensions = '.ps1', '.psm1', '.psd1', '.cs', '.xaml', '.resx', '.md', '.json', '.csproj', '.props'
        # Ohne Build-Ausgaben, Arbeitskopien der Subagenten, das Git-Verzeichnis und lokale Arbeitsordner.
        $skip = '\\(bin|obj|\.git|\.vs|node_modules|TestResults|worktrees|_arbeit)\\'
        # Nur der Pfad relativ zum Repository-Ordner zählt: Liegt die Kopie selbst unter .claude\worktrees\ (Arbeitskopie
        # eines Subagenten), würde der absolute Pfad sonst jede Datei ausschließen und die Prüfung liefe ins Leere.
        Get-ChildItem -LiteralPath $script:RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() -and $_.FullName.Substring($script:RepoRoot.Length) -notmatch $skip }
    }
}

Describe 'Quelldateien ohne rohe Steuerzeichen' {
    It 'erkennt rohe Steuerzeichen, auch C1, und lässt Tab, CR und LF zu' {
        $file = Join-Path $TestDrive 'probe.ps1'
        $clean = "a`tb`r`nc`n"
        [System.IO.File]::WriteAllText($file, $clean)
        @(Find-RawControlCharacter $file) | Should -BeNullOrEmpty

        foreach ($code in 0x00, 0x01, 0x08, 0x0B, 0x0C, 0x0E, 0x1B, 0x1F, 0x7F, 0x80, 0x9F) {
            [System.IO.File]::WriteAllText($file, "x`ny" + [char] $code + "z`n")
            $hit = @(Find-RawControlCharacter $file)
            $hit.Count | Should -Be 1 -Because ('U+{0:X4} muss gefunden werden' -f $code)
            $hit[0].Line | Should -Be 2
            $hit[0].Code | Should -Be ('U+{0:X4}' -f $code)
        }
    }

    It 'findet in der Repository-Struktur Quelldateien (Prüfung läuft nicht ins Leere)' {
        $files = @(Get-SourceFile)
        $files.Count | Should -BeGreaterThan 100
        ($files.Extension | Sort-Object -Unique) | Should -Contain '.ps1'
        ($files.Extension | Sort-Object -Unique) | Should -Contain '.cs'
    }

    It 'enthält keine Quelldatei rohe Steuerzeichen' {
        $problems = foreach ($file in Get-SourceFile) {
            foreach ($hit in Find-RawControlCharacter $file.FullName) {
                '{0}:{1} {2}' -f $hit.Path.Substring($script:RepoRoot.Length + 1), $hit.Line, $hit.Code
            }
        }
        $problems | Should -BeNullOrEmpty -Because ("rohe Steuerzeichen als Escape schreiben ([char]0x1F, \u001F):`n" + (@($problems) -join "`n"))
    }
}
