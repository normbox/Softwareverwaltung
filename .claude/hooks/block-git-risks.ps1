# PreToolUse (Bash, PowerShell): Git-Leitplanken aus CLAUDE.md (Git-Arbeitsweise, Merge macht der Benutzer).
#  - git commit / push / merge auf dem Branch main: blockiert. Ebenso ein push, der main als Ziel nennt.
#  - git push --force / -f / --force-with-lease, git reset --hard, git clean -f: immer blockiert (Rückfrage beim Benutzer).
#  - gh pr merge: blockiert (Merge führt der Benutzer selbst aus).
#  - git checkout -- <Pfad>: nur Hinweis (Exit 0), verwirft lokale Änderungen.
# Geprüft wird je Teilbefehl. Lässt sich der Branch nicht ermitteln, wird nicht blockiert (fail-open).
. (Join-Path $PSScriptRoot 'Common.ps1')

function Get-GitSubcommand {
    # Liefert Unterbefehl und restliche Argumente eines "git ..."-Teilbefehls (überspringt -C <Pfad>, -c <k=v>, Schalter).
    param([string] $Segment)
    $tokens = @($Segment -split '\s+' | Where-Object { $_ })
    $i = 1
    while ($i -lt $tokens.Count -and $tokens[$i].StartsWith('-')) {
        if ($tokens[$i] -in '-C', '-c', '--git-dir', '--work-tree') { $i += 2 } else { $i++ }
    }
    if ($i -ge $tokens.Count) { return $null }
    $rest = if ($i + 1 -lt $tokens.Count) { @($tokens[($i + 1)..($tokens.Count - 1)]) } else { @() }
    return [pscustomobject] @{ Name = $tokens[$i].ToLowerInvariant(); Args = $rest }
}

function Get-CurrentBranch {
    param([string] $Directory)
    try {
        if (-not $Directory -or -not (Test-Path -LiteralPath $Directory)) { return $null }
        $name = & git -C $Directory branch --show-current 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return ([string] $name).Trim()
    }
    catch { return $null }
}

try {
    $data = Read-HookInput
    $command = [string] $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }
    $directory = if ($data.cwd) { [string] $data.cwd } else { (Get-Location).Path }

    foreach ($segment in Split-ShellSegment $command) {
        $word = Get-CommandWord $segment

        if ($word -eq 'gh' -and $segment -match '(?i)\bpr\s+merge\b') {
            Stop-HookWithBlock 'Blockiert (gh pr merge): Den Merge führt der Benutzer selbst aus (UEBERGABE.md, Arbeitsregeln). Merge-Befehl nennen, nicht ausführen.'
        }
        if ($word -ne 'git') { continue }
        $git = Get-GitSubcommand $segment
        if (-not $git) { continue }
        $gitArgs = @($git.Args)

        $flagged = switch ($git.Name) {
            'push' {
                if ($gitArgs | Where-Object { $_ -in '--force', '-f', '--force-with-lease' -or $_ -like '--force-with-lease=*' -or $_ -like '+*' }) { 'git push mit --force/-f/--force-with-lease' }
            }
            'reset' { if ($gitArgs -contains '--hard') { 'git reset --hard' } }
            'clean' { if ($gitArgs | Where-Object { $_ -match '^-[a-zA-Z]*f' -or $_ -eq '--force' }) { 'git clean -f' } }
        }
        if ($flagged) {
            Stop-HookWithBlock "Blockiert ($flagged): Das ist schwer rückgängig zu machen. Erst den Benutzer fragen und den Befehl nennen, nicht ausführen."
        }

        if ($git.Name -in 'commit', 'push', 'merge') {
            $onMain = (Get-CurrentBranch $directory) -eq 'main'
            $pushToMain = $git.Name -eq 'push' -and ($gitArgs | Where-Object { $_ -match '(^|:|/)main$' })
            if ($onMain -or $pushToMain) {
                Stop-HookWithBlock ("Blockiert (git $($git.Name) auf main): main bleibt stabil, kein direktes Arbeiten (CLAUDE.md, Git-Arbeitsweise). " +
                    "Zuerst einen Branch anlegen (etappe-<nr>-<thema> oder ein Themenname), dort arbeiten und per Pull Request mergen.")
            }
        }

        if ($git.Name -eq 'checkout' -and $gitArgs -contains '--') {
            Write-HookNote 'Hinweis: git checkout -- <Pfad> verwirft lokale Änderungen an diesen Dateien unwiderruflich. Nur fortfahren, wenn das gewollt ist.'
        }
    }
    exit 0
}
catch { exit 0 }
