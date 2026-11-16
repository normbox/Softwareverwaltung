# Pester, PSScriptAnalyzer und xUnit mit eigenem APPDATA/LOCALAPPDATA.
# Grund: Jeder Import des Moduls räumt den App-Ordner auf (Selbstbereinigung, Migrationen);
# Tests und Probeläufe dürfen den echten Ordner des Benutzers nie verändern.
# Pester läuft standardmäßig nur auf tests/Unit; -IncludeIntegration nimmt tests/Integration dazu (liest das echte System).
#
# Voller Lauf (vor dem Abschluss eines Teilschritts und vor dem PR):
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 [-PesterOnly] [-XunitOnly] [-IncludeIntegration]
#
# Ende und Exit-Code: Als letzte Zeile steht immer "ISOLATED-TESTS-EXIT <Code>" (auch bei Abbruch und Fehlern). Darauf
# warten, nicht auf "kein dotnet-Prozess" (VS Code hält eigene dotnet-Prozesse offen). Code 0 = alles bestanden,
# 1 = Fehlschlag (Build, Pester, Analyzer, xUnit oder verändertes CIRCL-Verzeichnis), 2 = Abbruch durch die
# Parameterprüfung (es lief nichts), 3 = unerwarteter Fehler im Skript.
#
# Teilmengen (nur während der Arbeit; sie ersetzen den vollen Lauf nie):
#   -PesterPath <Pfad[]>   Pester nur auf diesen Dateien/Ordnern; sie müssen innerhalb von tests/ liegen (sonst Abbruch).
#                          Kein PSScriptAnalyzer und kein xUnit, außer mit -Analyzer bzw. -XunitFilter.
#   -XunitFilter <Ausdruck> nur xUnit, als dotnet test --filter (z. B. "FullyQualifiedName~BackupFolderRules").
#   -Analyzer              mit -PesterPath: PSScriptAnalyzer zusätzlich.
# Beispiele:
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -PesterPath tests/Unit/RegistryBackup.Tests.ps1
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -XunitFilter "FullyQualifiedName~AclRules"
param(
    [switch] $PesterOnly,
    [switch] $XunitOnly,
    [switch] $IncludeIntegration,
    [string[]] $PesterPath,
    [string] $XunitFilter,
    [switch] $Analyzer
)
$repo = Resolve-Path (Join-Path $PSScriptRoot '..')

# --- Teilmengen prüfen, bevor etwas gebaut oder verändert wird -------------------------------------------
$subset = [bool] $PesterPath -or $PSBoundParameters.ContainsKey('XunitFilter')
function Stop-Run([string] $Message) { [Console]::Error.WriteLine("Abbruch: $Message"); 'ISOLATED-TESTS-EXIT 2'; exit 2 }
if ($PSBoundParameters.ContainsKey('XunitFilter') -and [string]::IsNullOrWhiteSpace($XunitFilter)) { Stop-Run '-XunitFilter darf nicht leer sein.' }
if ($Analyzer -and -not $PesterPath) { Stop-Run '-Analyzer gilt nur zusammen mit -PesterPath (der volle Lauf enthält den Analyzer).' }
if ($subset -and $IncludeIntegration) { Stop-Run '-IncludeIntegration gilt nur im vollen Lauf, nicht mit -PesterPath/-XunitFilter.' }
if ($PesterPath -and $XunitOnly) { Stop-Run '-PesterPath und -XunitOnly schließen sich aus.' }
if ($PSBoundParameters.ContainsKey('XunitFilter') -and $PesterOnly) { Stop-Run '-XunitFilter und -PesterOnly schließen sich aus.' }
$testsRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'tests')).TrimEnd('\') + '\'
$pesterTargets = @()
foreach ($path in $PesterPath) {
    if ([string]::IsNullOrWhiteSpace($path) -or [WildcardPattern]::ContainsWildcardCharacters($path)) { Stop-Run "Ungültiger Pfad '$path' (leer oder mit Platzhaltern)." }
    $full = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }))
    if (-not $full.StartsWith($testsRoot, [StringComparison]::OrdinalIgnoreCase)) { Stop-Run "Der Pfad '$path' liegt nicht innerhalb von tests/." }
    if (-not (Test-Path -LiteralPath $full)) { Stop-Run "Der Pfad '$path' existiert nicht." }
    # Kein Link (Junction/Symlink) auf dem Weg: Sonst könnte ein Pfad unter tests/ aus tests/ hinausführen.
    for ($current = $full.TrimEnd('\'); $current.Length -ge $testsRoot.Length; $current = Split-Path -Parent $current) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Stop-Run "Der Pfad '$path' führt über einen Link (Junction/Symlink)." }
    }
    $pesterTargets += $full
}
$runPester = if ($subset) { [bool] $PesterPath } else { -not $XunitOnly }
$runXunit = if ($subset) { $PSBoundParameters.ContainsKey('XunitFilter') } else { -not $PesterOnly }
$runAnalyzer = if ($subset) { $Analyzer -and $runPester } else { $runPester }

$root = Join-Path ([System.IO.Path]::GetTempPath()) "softwareverwaltung-tests-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$userCircl = Join-Path $env:LOCALAPPDATA 'SoftwareInventory\cache\CIRCL'
$before = @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count
$saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
New-Item -ItemType Directory -Path "$root\Roaming", "$root\Local" -Force | Out-Null
$env:APPDATA = "$root\Roaming"; $env:LOCALAPPDATA = "$root\Local"
Set-Location $repo
$exitCode = 0
try {
    if ($subset) { 'TEILLAUF (Teilmenge): ersetzt nie den vollen Lauf vor Abschluss eines Teilschritts und vor dem PR.' }
    # Das Modul lädt lib\SoftwareInventory.Native.dll (RequiredAssemblies); vor Pester bauen.
    $buildOutput = @(dotnet build src/SoftwareInventory.Native -nologo -v q 2>&1)
    if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
    $buildOutput | Select-String -Pattern ' error ' | Select-Object -First 5
    if ($runPester) {
        $paths = if ($subset) { $pesterTargets } else { $p = @('tests/Unit'); if ($IncludeIntegration) { $p += 'tests/Integration' }; $p }
        $r = Invoke-Pester -Path $paths -Output None -PassThru
        'Pester: {0} bestanden, {1} fehlgeschlagen' -f $r.PassedCount, $r.FailedCount
        if ($r.FailedCount -gt 0) { $exitCode = 1 }
        if ($subset -and $r.TotalCount -eq 0) { 'WARNUNG: In den angegebenen Pfaden wurden keine Pester-Tests gefunden.' }
        $r.Failed | ForEach-Object { '--- ' + $_.ExpandedName; $_.ErrorRecord | ForEach-Object { $_.Exception.Message } }
    }
    if ($runAnalyzer) {
        $findings = @(Invoke-ScriptAnalyzer -Path ./src/SoftwareInventory -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
        'PSScriptAnalyzer: {0} Meldungen' -f $findings.Count
        if ($findings.Count -gt 0) { $exitCode = 1 }
    }
    if ($runXunit) {
        # Gesperrt ist die exe nur, wenn die App aus diesem Ordner läuft (eine Worktree-Kopie ist davon nicht betroffen).
        if (Get-Process Softwareverwaltung -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$repo\*" }) { 'xUnit übersprungen: die App läuft aus diesem Ordner und sperrt die exe.' }
        else {
            $testArguments = @('test', 'tests/Softwareverwaltung.App.Tests')
            if ($subset) { $testArguments += @('--filter', $XunitFilter) }
            $summary = @(& dotnet @testArguments 2>&1 | Select-String -Pattern 'Bestanden!|Fehler!|error|No test|Keine Tests' | Select-Object -First 10)
            if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
            $summary
            if ($subset -and $summary.Count -eq 0) { 'WARNUNG: xUnit meldete keine Zusammenfassung (Filter ohne Treffer?).' }
        }
    }
}
catch {
    "FEHLER im Testskript: $($_.Exception.Message)"
    $exitCode = 3
}
finally {
    $env:APPDATA = $saved.APPDATA; $env:LOCALAPPDATA = $saved.LOCALAPPDATA
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
$after = @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count
"CIRCL-Bestände beim Benutzer vorher/nachher: $before / $after (müssen gleich bleiben)"
if ($before -ne $after -and $exitCode -eq 0) { $exitCode = 1 }
"ISOLATED-TESTS-EXIT $exitCode"
exit $exitCode
