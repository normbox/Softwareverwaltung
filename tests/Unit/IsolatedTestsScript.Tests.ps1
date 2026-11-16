BeforeAll {
    $script:RunnerScript = Join-Path $PSScriptRoot '..\Invoke-IsolatedTests.ps1'
    function Invoke-Runner {
        # Startet das Testskript in einem eigenen Prozess. Die geprüften Fälle brechen vor dem Bauen und vor dem
        # Umlenken von APPDATA/LOCALAPPDATA ab; es läuft also nie ein Test. Geprüft wird auf ASCII-Wörter der
        # Meldungen, weil die Konsolencodierung Umlaute verändern kann.
        param([string[]] $Arguments)
        $output = & pwsh -NoProfile -File $script:RunnerScript @Arguments 2>&1 | Out-String
        @{ Output = $output; Exit = $LASTEXITCODE }
    }
}

Describe 'Invoke-IsolatedTests.ps1: Teilmengen (-PesterPath, -XunitFilter, -Analyzer)' {
    It 'bricht ab, wenn ein Pfad nicht innerhalb von tests/ liegt (<Path>)' -ForEach @(
        @{ Path = 'src' }
        @{ Path = '../src/SoftwareInventory/SoftwareInventory.psd1' }
        @{ Path = 'tests/../src' }
        @{ Path = '..' }
        @{ Path = 'tests-fremd' }
        @{ Path = 'C:\Windows' }
        @{ Path = 'tests' }
    ) {
        $r = Invoke-Runner @('-PesterPath', $Path)
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match 'Abbruch'
        $r.Output | Should -Not -Match 'Pester:'
    }

    It 'bricht ab, wenn ein Pfad unter tests/ nicht existiert, Platzhalter enthält oder leer ist' -ForEach @(
        @{ Path = 'tests/Unit/GibtEsNicht.Tests.ps1'; Match = 'existiert nicht' }
        @{ Path = 'tests/Unit/*.Tests.ps1'; Match = 'Platzhalter' }
        @{ Path = ' '; Match = 'leer' }
    ) {
        $r = Invoke-Runner @('-PesterPath', $Path)
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match $Match
    }

    It 'bricht ab, wenn der Pfad über eine Junction aus tests/ hinausführt' {
        $link = Join-Path $PSScriptRoot "..\Data\__link-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $target = Join-Path $TestDrive 'ausserhalb'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        & cmd.exe /c mklink /J "$link" "$target" | Out-Null
        try {
            $r = Invoke-Runner @('-PesterPath', (Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\Data')).Path (Split-Path -Leaf $link)))
            $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
            $r.Output | Should -Match 'Link'
        }
        finally {
            if (Test-Path -LiteralPath $link) { [System.IO.Directory]::Delete($link) }   # nur die Junction, nie das Ziel
        }
        Test-Path -LiteralPath $target | Should -BeTrue -Because 'das Ziel der Junction bleibt unberührt'
    }

    It 'lehnt widersprüchliche oder unvollständige Parameter ab (<Case>)' -ForEach @(
        @{ Case = '-XunitFilter leer'; Arguments = @('-XunitFilter', ' '); Match = 'darf nicht leer sein' }
        @{ Case = '-Analyzer ohne -PesterPath'; Arguments = @('-Analyzer'); Match = 'nur zusammen mit -PesterPath' }
        @{ Case = '-PesterPath mit -IncludeIntegration'; Arguments = @('-PesterPath', 'tests/Unit', '-IncludeIntegration'); Match = 'nur im vollen Lauf' }
        @{ Case = '-XunitFilter mit -IncludeIntegration'; Arguments = @('-XunitFilter', 'Name~X', '-IncludeIntegration'); Match = 'nur im vollen Lauf' }
        @{ Case = '-PesterPath mit -XunitOnly'; Arguments = @('-PesterPath', 'tests/Unit', '-XunitOnly'); Match = 'sich aus' }
        @{ Case = '-XunitFilter mit -PesterOnly'; Arguments = @('-XunitFilter', 'Name~X', '-PesterOnly'); Match = 'sich aus' }
    ) {
        $r = Invoke-Runner $Arguments
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match $Match
    }
}
