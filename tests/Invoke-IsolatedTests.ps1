# Pester, PSScriptAnalyzer und xUnit mit eigenem APPDATA/LOCALAPPDATA.
# Grund: Jeder Import des Moduls räumt den App-Ordner auf (Selbstbereinigung, Migrationen);
# Tests und Probeläufe dürfen den echten Ordner des Benutzers nie verändern.
# Pester läuft standardmäßig nur auf tests/Unit; -IncludeIntegration nimmt tests/Integration dazu (liest das echte System).
#
# Voller Lauf (vor dem Abschluss eines Teilschritts und vor dem PR):
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 [-PesterOnly] [-XunitOnly] [-IncludeIntegration]
#
# Ende und Exit-Code: Als letzte Zeile steht immer "ISOLATED-TESTS-EXIT <Code>" (auch bei Abbruch und Fehlern). Darauf
# warten, nicht auf "kein dotnet-Prozess" (VS Code hält eigene dotnet-Prozesse offen).
#   0 = alles bestanden
#   1 = Fehlschlag (Build, Pester einschließlich fehlgeschlagener Container/Blöcke, Analyzer, xUnit oder verändertes
#       CIRCL-Verzeichnis)
#   2 = Abbruch durch die Parameterprüfung (es lief nichts)
#   3 = unerwarteter Fehler im Skript
#   4 = nichts (oder nicht alles Angeforderte) ausgeführt: xUnit übersprungen, weil die App aus diesem Ordner läuft,
#       Pester-Ziel ohne Tests oder xUnit-Filter ohne Treffer; kein "bestanden"
#
# Teilmengen (nur während der Arbeit; sie ersetzen den vollen Lauf nie):
#   -PesterPath <Pfad[,Pfad]>  Pester nur auf diesen Dateien/Ordnern. Erlaubt sind nur *.Tests.ps1-Dateien und Ordner
#                              unter tests/Unit/ (nicht tests/Sandbox, nicht tests/Integration, keine Platzhalter, keine
#                              Links), sonst Abbruch. Mehrere Pfade mit Komma trennen. Kein PSScriptAnalyzer und kein
#                              xUnit, außer mit -Analyzer bzw. -XunitFilter.
#   -XunitFilter <Ausdruck>    nur xUnit, als dotnet test --filter (z. B. "FullyQualifiedName~BackupFolderRules").
#                              Erlaubt sind Buchstaben, Ziffern und . ~ = ! & | ( ) , + _ und Leerzeichen.
#   -Analyzer                  mit -PesterPath: PSScriptAnalyzer zusätzlich.
#   -ValidateOnly              nur die Parameter prüfen, nichts bauen oder ausführen (Exit 0 bei gültigen Parametern).
# Beispiele:
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -PesterPath tests/Unit/RegistryBackup.Tests.ps1
#   pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -XunitFilter "FullyQualifiedName~AclRules"
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch] $PesterOnly,
    [switch] $XunitOnly,
    [switch] $IncludeIntegration,
    [string[]] $PesterPath,
    [string] $XunitFilter,
    [switch] $Analyzer,
    [switch] $ValidateOnly,
    # Fängt Tippfehler (-PesterPaht) und Positionsargumente ab: Abbruch mit Abschlusszeile statt stiller Bindung.
    [Parameter(ValueFromRemainingArguments = $true)] [string[]] $Unexpected
)

function Stop-Run([int] $Code, [string] $Message) {
    # Über die Ausgabe (nicht [Console]::Error): So steht der Grund auch im Log bei `*> Datei`.
    "Abbruch: $Message"
    "ISOLATED-TESTS-EXIT $Code"
    exit $Code
}

# --- Parameter prüfen, bevor etwas gebaut oder verändert wird -------------------------------------------------
try {
    $repo = Resolve-Path (Join-Path $PSScriptRoot '..')
    if ($Unexpected) { Stop-Run 2 ('Unbekannte oder zusätzliche Argumente: ' + ($Unexpected -join ' ') + ' (Parameter siehe Kopf des Skripts).') }
    if ($PesterOnly -and $XunitOnly) { Stop-Run 2 '-PesterOnly und -XunitOnly schließen sich aus.' }
    $hasFilter = $PSBoundParameters.ContainsKey('XunitFilter')
    # Ohne -PesterPath bleibt die Liste leer (eine Pipeline mit $null ergäbe sonst ein leeres Element).
    $pathList = if ($PSBoundParameters.ContainsKey('PesterPath')) { @($PesterPath | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() }) } else { @() }
    if ($PesterPath -and $pathList.Count -eq 0) { Stop-Run 2 '-PesterPath ist leer.' }
    $subset = ($pathList.Count -gt 0) -or $hasFilter
    if ($hasFilter -and [string]::IsNullOrWhiteSpace($XunitFilter)) { Stop-Run 2 '-XunitFilter darf nicht leer sein.' }
    if ($hasFilter -and $XunitFilter -notmatch '^[\w.~=!&|(),+\s]+$') { Stop-Run 2 '-XunitFilter enthält nicht erlaubte Zeichen (erlaubt: Buchstaben, Ziffern, . ~ = ! & | ( ) , + _ und Leerzeichen).' }
    if ($Analyzer -and $pathList.Count -eq 0) { Stop-Run 2 '-Analyzer gilt nur zusammen mit -PesterPath (der volle Lauf enthält den Analyzer).' }
    if ($subset -and $IncludeIntegration) { Stop-Run 2 '-IncludeIntegration gilt nur im vollen Lauf, nicht mit -PesterPath/-XunitFilter.' }
    if ($pathList.Count -gt 0 -and $XunitOnly) { Stop-Run 2 '-PesterPath und -XunitOnly schließen sich aus.' }
    if ($hasFilter -and $PesterOnly) { Stop-Run 2 '-XunitFilter und -PesterOnly schließen sich aus.' }

    $testsRoot = [System.IO.Path]::GetFullPath((Join-Path $repo 'tests')).TrimEnd('\') + '\'
    $unitRoot = $testsRoot + 'Unit\'
    $pesterTargets = @()
    foreach ($path in $pathList) {
        if ([string]::IsNullOrWhiteSpace($path) -or [WildcardPattern]::ContainsWildcardCharacters($path)) { Stop-Run 2 "Ungültiger Pfad '$path' (leer oder mit Platzhaltern)." }
        # Ein Doppelpunkt nach dem Laufwerk (C:) wäre ein NTFS-Stream (datei.ps1:name) oder ein Gerätepfad.
        if ($path.Substring([Math]::Min(2, $path.Length)).Contains(':')) { Stop-Run 2 "Ungültiger Pfad '$path' (Doppelpunkt nach dem Laufwerk, Stream oder Gerätepfad)." }
        $full = [System.IO.Path]::GetFullPath($(if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path })).TrimEnd('\')
        # Nur tests/Unit: tests/Sandbox startet echte Installationen, tests/Integration liest das echte System.
        if (-not (($full + '\').StartsWith($unitRoot, [StringComparison]::OrdinalIgnoreCase))) { Stop-Run 2 "Der Pfad '$path' liegt nicht innerhalb von tests/Unit/." }
        if (-not (Test-Path -LiteralPath $full)) { Stop-Run 2 "Der Pfad '$path' existiert nicht." }
        # Kein Link (Junction/Symlink) auf dem Weg: Sonst könnte ein Pfad unter tests/Unit aus tests/ hinausführen.
        for ($current = $full; $current.Length -ge $testsRoot.Length; $current = Split-Path -Parent $current) {
            if ((Get-Item -LiteralPath $current -Force -ErrorAction Stop).Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Stop-Run 2 "Der Pfad '$path' führt über einen Link (Junction/Symlink)." }
        }
        if (Test-Path -LiteralPath $full -PathType Container) {
            # Pester steigt in Unterordner ab; auch dort keine Links.
            if (@(Get-ChildItem -LiteralPath $full -Recurse -Force -Attributes ReparsePoint -ErrorAction Stop).Count -gt 0) { Stop-Run 2 "Unter '$path' liegt ein Link (Junction/Symlink)." }
        }
        elseif ($full -notlike '*.Tests.ps1') {
            # Pester würde jede direkt genannte .ps1 ausführen, auch Nicht-Tests.
            Stop-Run 2 "Der Pfad '$path' ist keine *.Tests.ps1-Datei."
        }
        $pesterTargets += $full
    }
}
catch {
    "FEHLER bei der Parameterprüfung: $($_.Exception.Message)"
    'ISOLATED-TESTS-EXIT 3'
    exit 3
}
# SWV_ISOLATED_TESTS_CHILD=1 setzen die Tests dieses Skripts für ihre Kindprozesse: Sie enden nach der Prüfung, bauen und
# starten nie etwas (sonst könnte ein Rückschritt in der Prüfung eine Rekursion auslösen).
if ($ValidateOnly -or $env:SWV_ISOLATED_TESTS_CHILD -eq '1') {
    'Parameterprüfung bestanden (-ValidateOnly): Es wurde nichts gebaut oder ausgeführt.'
    'ISOLATED-TESTS-EXIT 0'
    exit 0
}

$runPester = if ($subset) { $pathList.Count -gt 0 } else { -not $XunitOnly }
$runXunit = if ($subset) { $hasFilter } else { -not $PesterOnly }
$runAnalyzer = if ($subset) { $Analyzer -and $runPester } else { $runPester }

$root = Join-Path ([System.IO.Path]::GetTempPath()) "softwareverwaltung-tests-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$saved = @{ APPDATA = $env:APPDATA; LOCALAPPDATA = $env:LOCALAPPDATA }
$userCircl = $null
$before = 0
$exitCode = 0
$notRun = $false
try {
    # Alles, was fehlschlagen kann, steht im try: Auch dann kommt die Abschlusszeile, und das finally setzt APPDATA zurück.
    $userCircl = Join-Path $env:LOCALAPPDATA 'SoftwareInventory\cache\CIRCL'
    $before = @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count
    New-Item -ItemType Directory -Path "$root\Roaming", "$root\Local" -Force | Out-Null
    $env:APPDATA = "$root\Roaming"; $env:LOCALAPPDATA = "$root\Local"
    Set-Location $repo
    if ($subset) { 'TEILLAUF (Teilmenge): ersetzt nie den vollen Lauf vor Abschluss eines Teilschritts und vor dem PR.' }
    # Das Modul lädt lib\SoftwareInventory.Native.dll (RequiredAssemblies); vor Pester bauen.
    $buildOutput = @(dotnet build src/SoftwareInventory.Native -nologo -v q 2>&1)
    if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
    $buildOutput | Select-String -Pattern ' error ' | Select-Object -First 5
    if ($runPester) {
        # Relativ zum Repo (der Arbeitsordner ist das Repo): Ein Repo-Pfad mit [ ] würde von Pester sonst als Platzhalter gelesen.
        $paths = if ($subset) { @($pesterTargets | ForEach-Object { $_.Substring($repo.Path.Length).TrimStart('\') }) } else { $p = @('tests/Unit'); if ($IncludeIntegration) { $p += 'tests/Integration' }; $p }
        $r = Invoke-Pester -Path $paths -Output None -PassThru
        'Pester: {0} bestanden, {1} fehlgeschlagen' -f $r.PassedCount, $r.FailedCount
        # Ein Syntaxfehler in einer Testdatei oder ein Fehler in BeforeAll/BeforeDiscovery zählt nicht als fehlgeschlagener
        # Test, sondern als fehlgeschlagener Container/Block: Das Gesamtergebnis entscheidet.
        if ($r.Result -ne 'Passed' -or $r.FailedCount -gt 0) {
            $exitCode = 1
            'Pester-Gesamtergebnis: {0} (fehlgeschlagene Container: {1}, Blöcke: {2})' -f $r.Result, $r.FailedContainersCount, $r.FailedBlocksCount
        }
        if ($subset -and $r.TotalCount -eq 0) { 'WARNUNG: In den angegebenen Pfaden wurden keine Pester-Tests gefunden.'; $notRun = $true }
        $r.Failed | ForEach-Object { '--- ' + $_.ExpandedName; $_.ErrorRecord | ForEach-Object { $_.Exception.Message } }
        $r.Containers | Where-Object { $_.Result -eq 'Failed' } | ForEach-Object { '--- Container: ' + $_.Name; $_.ErrorRecord | ForEach-Object { $_.Exception.Message } }
    }
    if ($runAnalyzer) {
        $findings = @(Invoke-ScriptAnalyzer -Path ./src/SoftwareInventory -Recurse -Settings ./PSScriptAnalyzerSettings.psd1)
        'PSScriptAnalyzer: {0} Meldungen' -f $findings.Count
        if ($findings.Count -gt 0) { $exitCode = 1 }
    }
    if ($runXunit) {
        # Gesperrt ist die exe nur, wenn die App aus diesem Ordner läuft (eine Worktree-Kopie ist davon nicht betroffen).
        if (Get-Process Softwareverwaltung -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$repo\*" }) {
            'xUnit übersprungen: die App läuft aus diesem Ordner und sperrt die exe.'
            $notRun = $true
        }
        else {
            # Eigener Ausgabeordner (im Temp-Ordner des Laufs, das finally räumt ihn auf): VS Code/C# Dev Kit baut das
            # WPF-Projekt parallel im selben obj-Ordner und verursachte sporadisch CS2001, BG1002 und MSB3061.
            # Bekannte Grenzen: Der Bau von SoftwareInventory.Native oben nutzt weiter das obj des Repos (klein, selten betroffen);
            # jeder Lauf baut kalt (neuer Restore mit dem Temp-APPDATA, also ohne die NuGet.Config des Benutzers).
            $testArguments = @('test', 'tests/Softwareverwaltung.App.Tests', '--artifacts-path', "$root\artifacts")
            if ($subset) { $testArguments += @('--filter', $XunitFilter) }
            # Erst die ganze Ausgabe einsammeln und den Exit-Code sichern, dann filtern: Ein vorzeitig beendetes
            # Select-Object darf $LASTEXITCODE nicht verfälschen und dotnet nicht abbrechen.
            $testOutput = @(& dotnet @testArguments 2>&1)
            $testExit = $LASTEXITCODE
            if ($testExit -ne 0) { $exitCode = 1 }
            # Zusammenfassung plus bei Fehlschlägen Testname und Meldung (Zeilen "Fehler <Test>", "Failed <Test>", Assert-Texte).
            $summary = @($testOutput | Select-String -Pattern 'Bestanden!|Fehler!|error|No test|Keine Tests|^\s*(Fehler|Failed)\s+\S|Assert\.|Expected|Actual|Exception' | Select-Object -First 40)
            $summary
            if ($subset -and $summary.Count -eq 0) { 'WARNUNG: xUnit meldete keine Zusammenfassung (Filter ohne Treffer?).'; $notRun = $true }
            if ($subset -and ($testOutput | Select-String -Pattern 'No test matches|Keine Tests')) { $notRun = $true }
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
    if (Test-Path -LiteralPath $root) {
        # Eine kurz noch gesperrte Datei (testhost, Virenscanner): einmal nach kurzer Pause erneut versuchen, sonst melden.
        Start-Sleep -Seconds 3
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $root) { "WARNUNG: Temp-Ordner des Laufs konnte nicht entfernt werden: $root" }
    }
}
$after = if ($userCircl) { @(Get-ChildItem -LiteralPath $userCircl -File -ErrorAction SilentlyContinue).Count } else { 0 }
"CIRCL-Bestände beim Benutzer vorher/nachher: $before / $after (müssen gleich bleiben)"
if ($before -ne $after -and $exitCode -eq 0) { $exitCode = 1 }
if ($notRun -and $exitCode -eq 0) { $exitCode = 4; 'Nicht alles Angeforderte wurde ausgeführt (Exit 4, kein "bestanden").' }
"ISOLATED-TESTS-EXIT $exitCode"
exit $exitCode
