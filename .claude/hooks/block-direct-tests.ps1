# PreToolUse (Bash, PowerShell): blockiert direkte Testläufe.
# Regel aus CLAUDE.md: Nie Invoke-Pester oder dotnet test direkt (das Skript setzt ein eigenes APPDATA/LOCALAPPDATA,
# damit der echte App-Ordner unberührt bleibt); Skripte aus tests/Sandbox nie starten.
# Erlaubt ist tests/Invoke-IsolatedTests.ps1. Geprüft wird je Teilbefehl (Trennung an ; && || | und Zeilenumbruch).
. (Join-Path $PSScriptRoot 'Common.ps1')

try {
    $data = Read-HookInput
    $command = [string] $data.tool_input.command
    if ([string]::IsNullOrWhiteSpace($command)) { exit 0 }

    foreach ($segment in Split-ShellSegment $command) {
        $word = Get-CommandWord $segment
        $reason = $null
        if ($word -eq 'invoke-pester') { $reason = 'Invoke-Pester' }
        elseif ($word -eq 'dotnet' -and $segment -match '(?i)^\S+\s+test\b') { $reason = 'dotnet test' }
        elseif ($word -in 'pwsh', 'powershell') {
            if ($segment -match '(?i)\bInvoke-Pester\b') { $reason = 'Invoke-Pester' }
            elseif ($segment -match '(?i)\bdotnet\s+test\b') { $reason = 'dotnet test' }
            elseif ($segment -match '(?i)tests[\\/]Sandbox[\\/]') { $reason = 'Skript aus tests/Sandbox' }
        }
        elseif ($segment -match '(?i)^[&.]?\s*["'']?\S*tests[\\/]Sandbox[\\/]\S+\.ps1') { $reason = 'Skript aus tests/Sandbox' }

        if ($reason) {
            Stop-HookWithBlock ("Blockiert ($reason): Tests nur über tests/Invoke-IsolatedTests.ps1 starten (eigenes APPDATA/LOCALAPPDATA, " +
                "Teilmengen mit -PesterPath/-XunitFilter, Ausgabe in eine Logdatei). Skripte aus tests/Sandbox nie starten (CLAUDE.md, Arbeitsteilung).")
        }
    }
    exit 0
}
catch { exit 0 }
