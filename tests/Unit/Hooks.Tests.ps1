BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:HookDir = Join-Path $script:RepoRoot '.claude\hooks'
    $script:Pwsh = (Get-Process -Id $PID).Path

    function Invoke-Hook {
        # Startet den Hook wie Claude Code: eigener Prozess, JSON auf stdin, Exit-Code und stderr/stdout auswerten.
        param([string] $Hook, [string] $StdIn)
        $info = [System.Diagnostics.ProcessStartInfo]::new($script:Pwsh)
        foreach ($a in '-NoProfile', '-NonInteractive', '-File', (Join-Path $script:HookDir "$Hook.ps1")) { $info.ArgumentList.Add($a) }
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.UseShellExecute = $false
        $info.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
        $process = [System.Diagnostics.Process]::Start($info)
        $process.StandardInput.Write($StdIn)
        $process.StandardInput.Close()
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw "Hook $Hook lief nicht in 60 s zu Ende." }
        [pscustomobject] @{ ExitCode = $process.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
    }

    function New-CommandInput {
        param([string] $Command, [string] $Cwd)
        @{ tool_name = 'Bash'; tool_input = @{ command = $Command }; cwd = $Cwd } | ConvertTo-Json -Compress -Depth 4
    }

    function New-FileInput {
        param([string] $Path)
        @{ tool_name = 'Write'; tool_input = @{ file_path = $Path } } | ConvertTo-Json -Compress -Depth 4
    }

    # Zwei kleine Git-Repositories (eines auf main, eines auf einem Themenbranch) für den Git-Hook.
    $script:MainRepo = Join-Path $TestDrive 'repo-main'
    $script:FeatureRepo = Join-Path $TestDrive 'repo-feature'
    foreach ($pair in @(@($script:MainRepo, 'main'), @($script:FeatureRepo, 'feature'))) {
        New-Item -ItemType Directory -Path $pair[0] | Out-Null
        & git -C $pair[0] init -q -b $pair[1] 2>&1 | Out-Null
    }
}

Describe 'Hook block-source-via-shell' {
    It 'blockiert (Exit 2): <Command>' -ForEach @(
        @{ Command = 'echo x > src/a.ps1' }
        @{ Command = 'cat <<EOF >> docs/x.md' }
        @{ Command = "sed -i 's/a/b/' src/a.cs" }
        @{ Command = 'Set-Content -Path src\a.ps1 -Value x' }
        @{ Command = "python -c ""open('a.json','w').write('x')""" }
        @{ Command = 'echo x | tee Window.xaml' }
    ) {
        $result = Invoke-Hook 'block-source-via-shell' (New-CommandInput $Command $script:RepoRoot)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match 'Blockiert'
    }

    It 'lässt durch (Exit 0): <Command>' -ForEach @(
        @{ Command = 'echo x > C:\Users\u\AppData\Local\Temp\claude\s\scratchpad\helper.ps1' }
        @{ Command = 'git status' }
        @{ Command = 'dotnet build src/App/App.csproj 2>&1' }
        @{ Command = 'ls *.cs' }
        @{ Command = 'grep -n foo a.cs > /dev/null' }
    ) {
        (Invoke-Hook 'block-source-via-shell' (New-CommandInput $Command $script:RepoRoot)).ExitCode | Should -Be 0
    }
}

Describe 'Hook block-direct-tests' {
    It 'blockiert (Exit 2): <Command>' -ForEach @(
        @{ Command = 'Invoke-Pester tests/Unit' }
        @{ Command = 'dotnet test src/Softwareverwaltung.sln' }
        @{ Command = 'pwsh -NoProfile -Command "Invoke-Pester"' }
        @{ Command = 'cd src && dotnet test' }
        @{ Command = '& tests/Sandbox/run.ps1' }
    ) {
        $result = Invoke-Hook 'block-direct-tests' (New-CommandInput $Command $script:RepoRoot)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match 'Invoke-IsolatedTests'
    }

    It 'lässt durch (Exit 0): <Command>' -ForEach @(
        @{ Command = 'pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -PesterPath tests/Unit/a.Tests.ps1 > log.txt 2>&1' }
        @{ Command = 'dotnet build src/a.csproj' }
        @{ Command = 'grep -rn Invoke-Pester docs' }
    ) {
        (Invoke-Hook 'block-direct-tests' (New-CommandInput $Command $script:RepoRoot)).ExitCode | Should -Be 0
    }
}

Describe 'Hook block-git-risks' {
    It 'blockiert auf main (Exit 2): <Command>' -ForEach @(
        @{ Command = 'git commit -m x' }
        @{ Command = 'git push origin main' }
        @{ Command = 'git -C . merge feature' }
    ) {
        $result = Invoke-Hook 'block-git-risks' (New-CommandInput $Command $script:MainRepo)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match 'main'
    }

    It 'blockiert immer (Exit 2): <Command>' -ForEach @(
        @{ Command = 'git push --force origin feature' }
        @{ Command = 'git push -f' }
        @{ Command = 'git push --force-with-lease' }
        @{ Command = 'git reset --hard HEAD~1' }
        @{ Command = 'git clean -fd' }
        @{ Command = 'git push origin HEAD:main' }
        @{ Command = 'gh pr merge 5 --repo a/b --merge' }
        @{ Command = '"C:\Program Files\GitHub CLI\gh.exe" pr merge 5 --repo a/b --merge' }
    ) {
        $result = Invoke-Hook 'block-git-risks' (New-CommandInput $Command $script:FeatureRepo)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match 'Blockiert'
    }

    It 'lässt auf einem Themenbranch durch (Exit 0): <Command>' -ForEach @(
        @{ Command = 'git commit -m x' }
        @{ Command = 'git push -u origin feature' }
        @{ Command = 'git status' }
    ) {
        (Invoke-Hook 'block-git-risks' (New-CommandInput $Command $script:FeatureRepo)).ExitCode | Should -Be 0
    }

    It 'lässt lesende Befehle auf main durch (Exit 0)' {
        (Invoke-Hook 'block-git-risks' (New-CommandInput 'git status' $script:MainRepo)).ExitCode | Should -Be 0
        (Invoke-Hook 'block-git-risks' (New-CommandInput 'git log --oneline' $script:MainRepo)).ExitCode | Should -Be 0
    }

    It 'gibt bei git checkout -- nur einen Hinweis (Exit 0)' {
        $result = Invoke-Hook 'block-git-risks' (New-CommandInput 'git checkout -- src/a.cs' $script:FeatureRepo)
        $result.ExitCode | Should -Be 0
        $result.StdErr | Should -Match 'Hinweis'
        $result.StdOut | Should -Match 'additionalContext'
    }
}

Describe 'Hook check-control-chars' {
    BeforeEach { $script:Probe = Join-Path $script:RepoRoot ("tests\Unit\_hookprobe_{0}.ps1" -f [guid]::NewGuid().ToString('N')) }
    AfterEach { Remove-Item -LiteralPath $script:Probe -ErrorAction SilentlyContinue }

    It 'blockiert (Exit 2) U+<Code> in einer Quelldatei im Repository' -ForEach @(
        @{ Code = 0x01 }, @{ Code = 0x1F }, @{ Code = 0x85 }, @{ Code = 0x200B }, @{ Code = 0x2028 }, @{ Code = 0x202E }
    ) {
        [System.IO.File]::WriteAllText($script:Probe, "a`r`nb" + [char] $Code + "c`r`n", [System.Text.UTF8Encoding]::new($false))
        $result = Invoke-Hook 'check-control-chars' (New-FileInput $script:Probe)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match ('Zeile 2: U\+{0:X4}' -f $Code)
    }

    It 'blockiert (Exit 2) eine Datei, die kein gültiges UTF-8 ist' {
        [System.IO.File]::WriteAllBytes($script:Probe, [byte[]] @(0x61, 0xE4, 0x62))
        $result = Invoke-Hook 'check-control-chars' (New-FileInput $script:Probe)
        $result.ExitCode | Should -Be 2 -Because $result.StdErr
        $result.StdErr | Should -Match 'UTF-8'
    }

    It 'lässt eine saubere Datei mit Umlauten, Tab, CRLF und BOM durch (Exit 0)' {
        [System.IO.File]::WriteAllText($script:Probe, "# " + [char] 0xE4 + [char] 0xF6 + "`t`r`nx`r`n", [System.Text.UTF8Encoding]::new($true))
        (Invoke-Hook 'check-control-chars' (New-FileInput $script:Probe)).ExitCode | Should -Be 0
    }

    It 'prüft nur Quelldateien im Repository (Exit 0 für andere Endung und für Dateien außerhalb)' {
        $other = Join-Path $script:RepoRoot ("tests\Unit\_hookprobe_{0}.dat" -f [guid]::NewGuid().ToString('N'))
        try {
            [System.IO.File]::WriteAllText($other, "a" + [char] 1)
            (Invoke-Hook 'check-control-chars' (New-FileInput $other)).ExitCode | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $other -ErrorAction SilentlyContinue }
        $outside = Join-Path $TestDrive 'outside.ps1'
        [System.IO.File]::WriteAllText($outside, "a" + [char] 1)
        (Invoke-Hook 'check-control-chars' (New-FileInput $outside)).ExitCode | Should -Be 0
    }
}

Describe 'Hooks sind fail-open' {
    It '<Hook> blockiert nicht bei unlesbarer Eingabe (Exit 0)' -ForEach @(
        @{ Hook = 'block-source-via-shell' }, @{ Hook = 'block-direct-tests' }, @{ Hook = 'block-git-risks' }, @{ Hook = 'check-control-chars' }
    ) {
        (Invoke-Hook $Hook 'das ist kein JSON').ExitCode | Should -Be 0
        (Invoke-Hook $Hook '').ExitCode | Should -Be 0
    }
}

Describe 'Hook-Konfiguration' {
    It 'trägt jeden Hook in .claude/settings.json ein, und die Skripte existieren' {
        $settings = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.claude\settings.json') -Raw | ConvertFrom-Json
        $commands = @(@($settings.hooks.PreToolUse) + @($settings.hooks.PostToolUse) | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
        foreach ($name in 'block-source-via-shell', 'block-direct-tests', 'block-git-risks', 'check-control-chars') {
            ($commands -match [regex]::Escape("$name.ps1")).Count | Should -Be 1 -Because "$name muss genau einmal eingetragen sein"
            Test-Path -LiteralPath (Join-Path $script:HookDir "$name.ps1") | Should -BeTrue
        }
    }
}
