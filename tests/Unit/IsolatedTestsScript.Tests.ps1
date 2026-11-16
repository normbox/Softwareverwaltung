BeforeAll {
    $script:RunnerScript = Join-Path $PSScriptRoot '..\Invoke-IsolatedTests.ps1'
    $script:Cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Prefix = '__isotest-'
    function Invoke-Runner {
        # Startet das Testskript in einem eigenen Prozess. Die geprüften Fälle brechen vor dem Bauen und vor dem
        # Umlenken von APPDATA/LOCALAPPDATA ab oder enden mit -ValidateOnly; es läuft also nie ein Test. Geprüft wird
        # auf ASCII-Wörter der Meldungen, weil die Konsolencodierung Umlaute verändern kann.
        # Jeder Kindprozess bekommt -ValidateOnly und die Sperre SWV_ISOLATED_TESTS_CHILD: Auch bei einem Rückschritt in der
        # Prüfung baut oder startet er nie etwas (keine Rekursion). Dieselbe pwsh wie der laufende Prozess.
        param([string[]] $Arguments)
        $env:SWV_ISOLATED_TESTS_CHILD = '1'
        $all = @($Arguments)
        if ($all -notcontains '-ValidateOnly') { $all += '-ValidateOnly' }   # ein Schalter darf nicht doppelt stehen
        try { $output = & $script:Pwsh -NoProfile -File $script:RunnerScript @all 2>&1 | Out-String }
        finally { Remove-Item Env:\SWV_ISOLATED_TESTS_CHILD -ErrorAction SilentlyContinue }
        @{ Output = $output; Exit = $LASTEXITCODE }
    }
    function New-Junction([string] $Link, [string] $Target) {
        & $script:Cmd /c mklink /J "$Link" "$Target" | Out-Null
    }
    function Remove-Leftovers {
        # Reste abgebrochener Läufe: erst Junctions (nur den Link, nie das Ziel), dann die Ordner.
        foreach ($item in Get-ChildItem -LiteralPath $PSScriptRoot -Filter "$($script:Prefix)*" -Force -ErrorAction SilentlyContinue) {
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
        @{ Path = 'tests/Unit/IsolatedTestsScript.Tests.ps1,tests/Sandbox/Start-ActionSandbox.ps1' }
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
        @{ Path = '\\?\C:\Windows'; Match = 'Platzhalter' }   # das ? ist ein Platzhalterzeichen
        @{ Path = 'tests/Unit/IsolatedTestsScript.Tests.ps1::$DATA'; Match = 'Doppelpunkt' }
        @{ Path = 'tests/Unit/IsolatedTestsScript.Tests.ps1:strom.Tests.ps1'; Match = 'Doppelpunkt' }
    ) {
        $r = Invoke-Runner @('-PesterPath', $Path)
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match $Match
    }

    It 'nimmt in tests/Unit keine .ps1 an, die keine *.Tests.ps1-Datei ist' {
        $plain = Join-Path $PSScriptRoot "$($script:Prefix)plain-$([guid]::NewGuid().ToString('N').Substring(0, 8)).ps1"
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
        $name = "$($script:Prefix)link-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
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
        $name = "$($script:Prefix)dir-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
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
        @{ Case = '-PesterOnly mit -XunitOnly'; Arguments = @('-PesterOnly', '-XunitOnly'); Match = 'sich aus' }
        @{ Case = 'Tippfehler im Parameternamen'; Arguments = @('-PesterPaht', 'tests/Unit'); Match = 'Unbekannte' }
        @{ Case = 'Positionsargument'; Arguments = @('tests/Unit/IsolatedTestsScript.Tests.ps1'); Match = 'Unbekannte' }
    ) {
        $r = Invoke-Runner $Arguments
        $r.Exit | Should -Be 2
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 2'
        $r.Output | Should -Match $Match
    }

    It 'nimmt den vollen Aufruf ohne Teilmengen-Parameter an und hält ihn für keinen Teillauf (<Case>)' -ForEach @(
        @{ Case = 'ohne Parameter'; Arguments = @('-ValidateOnly') }
        @{ Case = '-IncludeIntegration'; Arguments = @('-IncludeIntegration', '-ValidateOnly') }
        @{ Case = '-PesterOnly'; Arguments = @('-PesterOnly', '-ValidateOnly') }
        @{ Case = '-XunitOnly'; Arguments = @('-XunitOnly', '-ValidateOnly') }
        @{ Case = '-PesterOnly mit -IncludeIntegration'; Arguments = @('-PesterOnly', '-IncludeIntegration', '-ValidateOnly') }
    ) {
        $r = Invoke-Runner $Arguments
        $r.Exit | Should -Be 0
        $r.Output | Should -Match 'ISOLATED-TESTS-EXIT 0'
        $r.Output | Should -Not -Match 'Abbruch'
    }
}
