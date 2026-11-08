# Geschützte Kopie des Helfers unter Program Files\Softwareverwaltung\Helper\<Version>.
# Liegt die App in einem beschreibbaren Ordner (ZIP, Debug-Build), könnte Schadsoftware den Helfer
# dort austauschen. Deshalb startet die App nur eine Kopie, die am Zielort geprüft wurde:
# Pfad, Ordnerrechte und im Release ausschließlich die Signatur (nur Debug-Builds auch über den Hash).
# Angelegt wird sie mit einem Werkzeug aus System32, damit die Exe aus dem beschreibbaren Ordner nicht erhöht läuft.

$script:HelperFileName = 'SoftwareInventory.Helper.exe'
$script:HelperCopyToolTimeoutSeconds = 120

function Get-HelperCopyRoot {
    Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Softwareverwaltung\Helper'
}

function Get-HelperCopyPath {
    Join-Path (Join-Path (Get-HelperCopyRoot) ([string] (Get-SoftwareInventoryVersion))) $script:HelperFileName
}

function Test-HelperDebugBuild {
    [SoftwareInventory.BuildInfo]::IsDebugBuild
}

function Test-HelperSignatureValid {
    param([string] $Path)
    try { (Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop).Status -eq 'Valid' }
    catch {
        Write-Verbose "Signatur nicht lesbar: $_"
        $false
    }
}

function Test-HelperCopyTrusted {
    <#
    .SYNOPSIS
        Darf diese Kopie erhöht gestartet werden? Geprüft wird immer die Kopie am Zielort.
    .DESCRIPTION
        Im Release zählt ausschließlich die Signatur. Der Vergleich mit der Quelle gilt nur für Debug-Builds.
    #>
    param([string] $Path, [string] $Source)
    try {
        $root = (Get-HelperCopyRoot).TrimEnd('\')
        if (-not $Path.StartsWith("$root\", [StringComparison]::OrdinalIgnoreCase)) { return $false }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
        foreach ($target in @($Path, (Split-Path -Parent $Path), $root)) {
            if (Test-UserWritablePath $target) { return $false }
        }
        if (Test-HelperDebugBuild) { return (Get-FileHash -LiteralPath $Path).Hash -eq (Get-FileHash -LiteralPath $Source).Hash }
        Test-HelperSignatureValid $Path
    }
    catch {
        Write-Verbose "Kopie des Helfers nicht prüfbar: $_"
        $false
    }
}

function Test-HelperCopyPossible {
    # Ohne gültige Signatur ließe sich eine Release-Kopie nie anerkennen; dann gar nicht erst nachfragen.
    param([string] $Source)
    (Test-HelperDebugBuild) -or (Test-HelperSignatureValid $Source)
}

function Find-OlderHelperCopy {
    # Höchste vorhandene andere Version, die selbst noch gültig ist. Nur im Release: Unsignierte Kopien tauschen nichts aus.
    if (Test-HelperDebugBuild) { return $null }
    $root = Get-HelperCopyRoot
    if (-not (Test-Path -LiteralPath $root)) { return $null }
    $own = [string] (Get-SoftwareInventoryVersion)
    Get-ChildItem -LiteralPath $root -Directory | Where-Object { $_.Name -match '^\d+(\.\d+){1,3}$' -and $_.Name -ne $own } |
        Sort-Object { [version] $_.Name } -Descending | ForEach-Object {
            $path = Join-Path $_.FullName $script:HelperFileName
            if (Test-HelperCopyTrusted -Path $path -Source $path) { $path }
        } | Select-Object -First 1
}

function Invoke-ElevatedSystemTool {
    <#
    .SYNOPSIS
        Startet ein Werkzeug aus System32 erhöht, ohne Fenster und mit System32 als Arbeitsordner.
    .OUTPUTS
        Exit-Code oder $null, wenn es nicht rechtzeitig fertig wurde. UAC abgelehnt: Win32Exception 1223.
    #>
    param([Parameter(Mandatory)] [string] $Tool, [Parameter(Mandatory)] [string] $Arguments)
    $system = [Environment]::GetFolderPath('System')
    $owner = (Get-Process -Id $PID).MainWindowHandle
    $process = [SoftwareInventory.ElevationInterop]::StartTool((Join-Path $system $Tool), $Arguments, $owner, $system)
    try {
        $deadline = [datetime]::UtcNow.AddSeconds($script:HelperCopyToolTimeoutSeconds)
        while (-not $process.HasExited) {
            if ([datetime]::UtcNow -ge $deadline) { return $null }
            Start-Sleep -Milliseconds 100
        }
        $process.ExitCode
    }
    finally { $process.Dispose() }
}

function Write-HelperCopyLog {
    # Auch das Anlegen und Entfernen ist eine Aktion mit Administratorrechten und wird protokolliert.
    param([string] $Action, [string] $Result, $Message, [string] $Path)
    $now = [datetime]::UtcNow.ToString('o')
    Write-ActionLogEntry -Phase Completed -Data ([ordered] @{
            ActionId = [guid]::NewGuid().ToString(); Action = $Action; Name = 'SoftwareInventory.Helper'; Method = 'SystemTool'
            FilePath = $Path; Elevated = $true; Result = $Result; Message = $Message; StartedAt = $now; CompletedAt = $now
        })
}

function New-HelperCopy {
    # robocopy legt fehlende Ordner an, die Rechte erbt die Kopie von „Programme“. Exit-Code unter 8 heißt Erfolg.
    param([string] $Source, [string] $Target)
    $arguments = '"{0}" "{1}" {2} /R:1 /W:1 /NP /NJH /NJS' -f (Split-Path -Parent $Source), (Split-Path -Parent $Target), $script:HelperFileName
    $exit = Invoke-ElevatedSystemTool -Tool 'robocopy.exe' -Arguments $arguments
    $null -ne $exit -and $exit -lt 8
}

function Resolve-ElevatedHelperPath {
    <#
    .SYNOPSIS
        Wählt die Exe, die gestartet wird, und legt die geschützte Kopie bei Bedarf an.
    .OUTPUTS
        @{ Path; IsCopy } oder @{ Status; Error }, wenn nichts gestartet werden soll. Geht die Kopie nicht,
        bleibt es beim Helfer im App-Ordner; davor hat die Bestätigung gewarnt.
    #>
    param([switch] $NoElevation, [System.Collections.IDictionary] $Control)
    $source = [System.IO.Path]::GetFullPath($script:ElevatedHelperPath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { return @{ Status = 'Failed'; Error = (New-InventoryMessage HelperFileMissing $source) } }
    $plain = @{ Path = $source; IsCopy = $false }
    if ($NoElevation -or -not (Test-UserWritablePath $source)) { return $plain }

    $copy = Get-HelperCopyPath
    if (Test-HelperCopyTrusted -Path $copy -Source $source) { return @{ Path = $copy; IsCopy = $true } }
    # Vorhanden, aber nicht anerkannt (veralteter Debug-Build oder verändert): nichts überschreiben, die Warnung bleibt.
    if ((Test-Path -LiteralPath $copy) -or -not (Test-HelperCopyPossible $source)) { return $plain }

    try {
        Set-ActionPhase $Control 'WaitingForElevation'
        $older = Find-OlderHelperCopy
        if ($older) {
            $run = Start-ElevatedHelper -HelperPath $older -TimeoutSeconds 120 -HelperPlan @{ Operation = 'ReplaceHelperCopy'; SourcePath = $source; TargetVersion = [string] (Get-SoftwareInventoryVersion); RestorePoint = $false }
            if ($run.Status -eq 'ElevationDenied') { return $run }
            $action = 'ReplaceHelperCopy'
            $failure = if ($run.Status -ne 'Completed' -or $run.Error) { $run.Error } else { $null }
        }
        else {
            $created = New-HelperCopy -Source $source -Target $copy
            $action = 'CreateHelperCopy'
            $failure = if (-not $created) { New-InventoryMessage HelperCopyCreateFailed } else { $null }
        }
    }
    catch {
        if (Test-ElevationCancelled $_) { return @{ Status = 'ElevationDenied'; Error = (New-InventoryMessage ElevationDenied) } }
        $action = 'CreateHelperCopy'
        $failure = New-InventoryMessage HelperCopyCreateFailed
    }

    if (-not $failure -and (Test-HelperCopyTrusted -Path $copy -Source $source)) {
        Write-HelperCopyLog -Action $action -Result 'Succeeded' -Message (New-InventoryMessage HelperCopyReady $copy) -Path $copy
        return @{ Path = $copy; IsCopy = $true }
    }
    if (-not $failure) { $failure = New-InventoryMessage HelperCopyCheckFailed }
    Write-HelperCopyLog -Action $action -Result 'Failed' -Message $failure -Path $copy
    $plain
}
