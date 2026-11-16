# Pester, PSScriptAnalyzer und xUnit mit eigenem APPDATA/LOCALAPPDATA.
# Grund: Jeder Import des Moduls räumt den App-Ordner auf (Selbstbereinigung, Migrationen);
# Tests und Probeläufe dürfen den echten Ordner des Benutzers nie verändern.
# Pester läuft standardmäßig nur auf tests/Unit; -IncludeIntegration nimmt tests/Integration dazu (liest das echte System).
# Aufruf: pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 [-PesterOnly] [-XunitOnly] [-IncludeIntegration]
param([switch] $PesterOnly, [switch] $XunitOnly, [switch] $IncludeIntegration)
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')
$root = Join-Path ([System.IO.Path]::GetTempPath()) "softwareverwaltung-tests-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$userCircl = Join-Path $env:LOCALAPPDATA 'SoftwareInventory\cache\CIRCL'
$before = @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count
$saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
New-Item -ItemType Directory -Path "$root\Roaming", "$root\Local" -Force | Out-Null
$env:APPDATA = "$root\Roaming"; $env:LOCALAPPDATA = "$root\Local"
Set-Location $repo
try {
    # Das Modul lädt lib\SoftwareInventory.Native.dll (RequiredAssemblies); vor Pester bauen.
    dotnet build src/SoftwareInventory.Native -nologo -v q | Select-String -Pattern ' error ' | Select-Object -First 5
    if (-not $XunitOnly) {
        $paths = @('tests/Unit'); if ($IncludeIntegration) { $paths += 'tests/Integration' }
        $r = Invoke-Pester -Path $paths -Output None -PassThru
        'Pester: {0} bestanden, {1} fehlgeschlagen' -f $r.PassedCount, $r.FailedCount
        $r.Failed | ForEach-Object { '--- ' + $_.ExpandedName; $_.ErrorRecord | ForEach-Object { $_.Exception.Message } }
        'PSScriptAnalyzer: {0} Meldungen' -f @(Invoke-ScriptAnalyzer -Path ./src/SoftwareInventory -Recurse -Settings ./PSScriptAnalyzerSettings.psd1).Count
    }
    if (-not $PesterOnly) {
        # Gesperrt ist die exe nur, wenn die App aus diesem Ordner läuft (eine Worktree-Kopie ist davon nicht betroffen).
        if (Get-Process Softwareverwaltung -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$repo\*" }) { 'xUnit übersprungen: die App läuft aus diesem Ordner und sperrt die exe.' }
        else { dotnet test tests/Softwareverwaltung.App.Tests 2>&1 | Select-String -Pattern 'Bestanden!|Fehler!|error' | Select-Object -First 10 }
    }
}
finally {
    $env:APPDATA = $saved.APPDATA; $env:LOCALAPPDATA = $saved.LOCALAPPDATA
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
$after = @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count
"CIRCL-Bestände beim Benutzer vorher/nachher: $before / $after (müssen gleich bleiben)"
