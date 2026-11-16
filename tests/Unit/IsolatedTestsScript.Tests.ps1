BeforeAll {
    $script:RunnerScript = Join-Path $PSScriptRoot '..\Invoke-IsolatedTests.ps1'
    $script:Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    function Invoke-Runner {
        # Startet das Testskript in einem eigenen Prozess. Die geprüften Fälle brechen vor dem Bauen und vor dem
        # Umlenken von APPDATA/LOCALAPPDATA ab oder enden mit -ValidateOnly; es läuft also nie ein Test. Geprüft wird
        # auf ASCII-Wörter der Meldungen, weil die Konsolencodierung Umlaute verändern kann.
        param([string[]] $Arguments)
        $output = & pwsh -NoProfile -File $script:RunnerScript @Arguments 2>&1 | Out-String
        @{ Output = $output; Exit = $LASTEXITCODE }
    }
    function New-Junction([string] $Link, [string] $Target) {
        & $script:Cmd /c mklink /J "$Link" "$Target" | Out-Null
    }
    function Remove-Leftovers {
        # Reste abgebrochener Läufe: erst Junctions (nur den Link, nie das Ziel), dann die Ordner.
        foreach ($item in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '__*' -Force -ErrorAction SilentlyContinue) {
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { [System.IO.Directory]::Delete($item.FullName) }
            elseif ($item.PSIsContainer) {
                foreach ($inner in Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue) {
                    if ($inner.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { [System.IO.Directory]::Delete($inner.FullName) }
                }
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
            else { Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue }
        }
    }
    Remove-Leftovers
}

AfterAll { Remove-Leftovers }

Describe 'Invoke-IsolatedTests.ps1: Teilmengen (-PesterPath, -XunitFilter, -Analyzer, -ValidateOnly)' {
    It 'lässt nur tests/Unit zu, nie tests/Sandbox, tests/Integration oder das Skript selbst (<Path>)' -ForEach @(
        @{ Path = 'src' }
        @{ Path = '../src/SoftwareInventory/SoftwareInventory.psd1' }
        @{ Path = 'tests/../src' }
        @{ Path = '..' }
        @{ Path = 'tests-fremd' }
        @{ Path = 'C:\Windows' }
        @{ Path = 'tests' }
        @{ Path = 'tests/' }
        @{ Path = 'tests/Integration' }
        @{ Path = 'tests/Sandbox' }
        @{ Path = 'tests/Sandbox/Start-ActionSandbox.ps1' }
        @{ Path = 'tests/Sandbox/Start-AppSandbox.ps1' }
        @{ Path = 'tests/Invoke-IsolatedTests.ps1' }
        @{ Path = 'tests/Unit/../Sandbox/Start-ActionSandbox.ps1' }
        @{ Path = 'tests\Unit\..\Integration' }
        @{ Path = 'tests/Unit-fremd' }
    ) {
        $r = Invoke-Runner @('-PesterPath', $Path)
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'Abbruch'
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match 'nicht innerhalb'
        $r.Output | Should -Not -Match 'Pester:'
    }

    It 'bricht ab, wenn ein Pfad unter tests/Unit nicht existiert, Platzhalter enthält oder leer ist' -ForEach @(
        @{ Path = 'tests/Unit/GibtEsNicht.Tests.ps1'; Match = 'existiert nicht' }
        @{ Path = 'tests/Unit/*.Tests.ps1'; Match = 'Platzhalter' }
        @{ Path = ' '; Match = 'leer' }
    ) {
        $r = Invoke-Runner @('-PesterPath', $Path)
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match $Match
    }

    It 'nimmt in tests/Unit keine .ps1 an, die keine *.Tests.ps1-Datei ist' {
        $plain = Join-Path $PSScriptRoot "__plain-$([guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
        'Write-Output "darf nie laufen"' | Set-Content -LiteralPath $plain
        try {
            $r = Invoke-Runner @('-PesterPath', "tests/Unit/$(Split-Path -Leaf $plain)")
            $r.Exit | Should -Be 2
            $r.Output | Should -Match 'Tests.ps1-Datei'
            $r.Output | Should -Not -Match 'darf nie laufen'
        }
        finally { Remove-Item -LiteralPath $plain -Force -ErrorAction SilentlyContinue }
    }

    It 'bricht ab, wenn der Pfad selbst eine Junction ist' {
        $name = "__link-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $target = Join-Path $TestDrive 'ausserhalb'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        New-Junction (Join-Path $PSScriptRoot $name) $target
        try {
            $r = Invoke-Runner @('-PesterPath', "tests/Unit/$name")
            $r.Exit | Should -Be 2
            $r.Output | Should -Match 'Link'
        }
        finally { Remove-Leftovers }
        Test-Path -LiteralPath $target | Should -BeTrue -Because 'das Ziel der Junction bleibt unberührt'
    }

    It 'bricht ab, wenn in einem angegebenen Ordner eine Junction liegt (Pester würde hineinsteigen)' {
        $name = "__dir-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        $folder = Join-Path $PSScriptRoot $name
        $target = Join-Path $TestDrive 'ausserhalb2'
        New-Item -ItemType Directory -Path $folder, $target -Force | Out-Null
        New-Junction (Join-Path $folder 'abzweig') $target
        try {
            $r = Invoke-Runner @('-PesterPath', "tests/Unit/$name")
            $r.Exit | Should -Be 2
            $r.Output | Should -Match 'Link'
        }
        finally { Remove-Leftovers }
        Test-Path -LiteralPath $target | Should -BeTrue
    }

    It 'nimmt gültige Pfade und Filter an (nur Prüfung mit -ValidateOnly) (<Case>)' -ForEach @(
        @{ Case = 'eine Testdatei'; Arguments = @('-PesterPath', 'tests/Unit/IsolatedTestsScript.Tests.ps1', '-ValidateOnly') }
        @{ Case = 'der Ordner tests/Unit'; Arguments = @('-PesterPath', 'tests/Unit', '-ValidateOnly') }
        @{ Case = 'der Ordner mit Schrägstrich'; Arguments = @('-PesterPath', 'tests/Unit/', '-ValidateOnly') }
        @{ Case = 'zwei Dateien, mit Komma getrennt'; Arguments = @('-PesterPath', 'tests/Unit/IsolatedTestsScript.Tests.ps1,tests/Unit/RegistryBackup.Tests.ps1', '-ValidateOnly') }
        @{ Case = 'mit Analyzer'; Arguments = @('-PesterPath', 'tests/Unit/IsolatedTestsScript.Tests.ps1', '-Analyzer', '-ValidateOnly') }
        @{ Case = 'ein xUnit-Filter'; Arguments = @('-XunitFilter', 'FullyQualifiedName~BackupFolderRules&Name!~Junction', '-ValidateOnly') }
        @{ Case = 'Pester und xUnit zusammen'; Arguments = @('-PesterPath', 'tests/Unit/IsolatedTestsScript.Tests.ps1', '-XunitFilter', 'FullyQualifiedName~Acl', '-ValidateOnly') }
    ) {
        $r = Invoke-Runner $Arguments
        $r.Exit | Should -Be 0
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 0'
        $r.Output | Should -Match 'ValidateOnly'
        $r.Output | Should -Not -Match 'Pester:'
    }

    It 'lehnt unzulässige Zeichen im xUnit-Filter ab (<Filter>)' -ForEach @(
        @{ Filter = '--settings x.runsettings' }
        @{ Filter = '-p:Foo=bar' }
        @{ Filter = 'a;b' }
        @{ Filter = 'a"b' }
        @{ Filter = 'a`b' }
        @{ Filter = '$(x)' }
    ) {
        # Mit Doppelpunkt, damit ein Wert mit führendem - nicht als eigener Parameter gelesen wird.
        $r = Invoke-Runner @("-XunitFilter:$Filter", '-ValidateOnly')
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match 'nicht erlaubte'
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

    It 'bindet Positionsargumente nicht still an einen Parameter (kein versehentlicher Teillauf)' {
        $r = Invoke-Runner @('tests/Unit/IsolatedTestsScript.Tests.ps1')
        $r.Exit | Should -Not -Be 0
        $r.Output | Should -Not -Match 'TEILLAUF'
        $r.Output | Should -Not -Match 'Pester:'
    }
}
