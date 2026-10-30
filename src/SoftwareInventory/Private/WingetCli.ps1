# winget als Kommandozeilenprogramm für Aktionen. Das Inventar nutzt Microsoft.WinGet.Client;
# für Aktualisieren/Deinstallieren wird winget.exe direkt gestartet, weil das auch im erhöhten
# Helfer unter Windows PowerShell 5.1 ohne zusätzliches Modul funktioniert.

function Get-WingetExecutable {
    <#
    .SYNOPSIS
        Pfad zu winget.exe im Paketordner von App Installer, oder $null.
    .DESCRIPTION
        Der übliche Aufruf „winget“ geht über einen Alias in %LOCALAPPDATA%\Microsoft\WindowsApps.
        Den gibt es im Profil eines anderen Administratorkontos (UAC mit anderem Konto) nicht.
        Deshalb wird der echte Pfad unter %ProgramFiles%\WindowsApps verwendet; dieser Ordner
        ist nur für Administratoren beschreibbar.
    #>
    try {
        $package = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction Stop |
            Sort-Object { [version] $_.Version } -Descending | Select-Object -First 1
    }
    catch {
        Write-Verbose "App Installer nicht abfragbar: $_"
        return $null
    }
    if (-not $package -or -not $package.InstallLocation) { return $null }
    $path = Join-Path $package.InstallLocation 'winget.exe'
    if (Test-Path -LiteralPath $path -PathType Leaf) { $path } else { $null }
}

function Get-WingetClientProblem {
    <#
    .SYNOPSIS
        Grund, warum die Cmdlets von Microsoft.WinGet.Client nicht nutzbar sind, oder $null.
    .DESCRIPTION
        Die App liefert das Modul mit; winget selbst (App Installer) kann trotzdem fehlen. Die
        Cmdlets sprechen winget über COM an und dürfen dann gar nicht erst aufgerufen werden.
    #>
    param([string] $Command = 'Get-WinGetPackage')
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { return New-InventoryMessage WingetClientModuleMissing }
    if (-not (Get-WingetExecutable)) { return New-InventoryMessage WingetClientNotInstalled }
    $null
}

function ConvertTo-ArgumentString {
    # Baut aus einzelnen Argumenten eine Befehlszeile nach den Regeln von CommandLineToArgvW.
    param([string[]] $Argument)
    $parts = foreach ($a in $Argument) {
        if ($a -and $a -notmatch '[\s"]') { $a; continue }
        # Backslashes vor Anführungszeichen verdoppeln, Anführungszeichen maskieren.
        $escaped = [regex]::Replace($a, '(\\*)"', { param($m) $m.Groups[1].Value * 2 + '\"' })
        $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
        '"' + $escaped + '"'
    }
    $parts -join ' '
}

# winget: „Kein installiertes Paket gefunden, das den Eingabekriterien entspricht“ (0x8A150014)
$script:WingetNoPackageFound = -1978335212

function Invoke-WingetCli {
    # Ruft winget.exe nur lesend auf (z. B. „list“); liefert ExitCode und Ausgabezeilen.
    param([Parameter(Mandatory)] [string[]] $Argument)
    $winget = Get-WingetExecutable
    if (-not $winget) { return @{ ExitCode = $null; Lines = @() } }
    try {
        $lines = @(& $winget @Argument 2>&1 | ForEach-Object { "$_" })
        @{ ExitCode = $LASTEXITCODE; Lines = $lines }
    }
    catch {
        Write-Verbose "winget nicht aufrufbar: $($_.Exception.Message)"
        @{ ExitCode = $null; Lines = @() }
    }
}

function Get-WingetListRow {
    # Datenzeilen einer winget-Tabelle (nach der Trennlinie aus Bindestrichen), ohne Fortschrittsreste.
    param([string[]] $Line)
    $separator = [array]::FindIndex([string[]] @($Line), [Predicate[string]] { param($l) $l -match '^\s*-{5,}\s*$' })
    if ($separator -lt 0) { return @() }
    @($Line | Select-Object -Skip ($separator + 1) | Where-Object { $_.Trim() })
}

function Resolve-WingetTargetId {
    <#
    .SYNOPSIS
        Welche ID winget für upgrade/uninstall mit „--exact“ braucht; $null, wenn winget das Paket so nicht findet.
    .DESCRIPTION
        Nur lesend über „winget list --id … --exact --source …“. Findet winget die Katalog-ID, bleibt sie.
        Meldet winget „nicht gefunden“, wird die lokale Kennung aus dem Registry-Eintrag versucht
        (Get-WingetLocalId); sie gilt nur, wenn winget damit genau einen Eintrag liefert, dessen angezeigte
        ID ohne Rücksicht auf Groß-/Kleinschreibung genau der Katalog-ID entspricht. Ohne „--exact“ wird
        nie gesucht. Store-Pakete (msstore) werden nicht geprüft, weil die Abfrage sonst der
        Store-Vereinbarung zustimmen würde. Andere Fehler von winget ändern nichts (Katalog-ID bleibt).
    .OUTPUTS
        @{ Id; Local } oder $null.
    #>
    param([Parameter(Mandatory)] $Record, [Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Source)
    if ($Source -eq 'msstore') { return @{ Id = $Id; Local = $false } }
    $common = @('--exact', '--source', $Source, '--accept-source-agreements', '--disable-interactivity')
    $direct = Invoke-WingetCli -Argument (@('list', '--id', $Id) + $common)
    if ($direct.ExitCode -ne $script:WingetNoPackageFound) { return @{ Id = $Id; Local = $false } }

    $local = Get-WingetLocalId $Record
    if (-not $local) { return $null }
    $byLocal = Invoke-WingetCli -Argument (@('list', '--id', $local) + $common)
    if ($byLocal.ExitCode -ne 0) { return $null }
    $rows = @(Get-WingetListRow $byLocal.Lines)
    $same = @($rows | Where-Object { @($_ -split '\s+') -contains $Id })   # -contains vergleicht ohne Groß/Klein
    if ($rows.Count -eq 1 -and $same.Count -eq 1) { return @{ Id = $local; Local = $true } }
    $null
}

function Get-WingetArgument {
    <#
    .SYNOPSIS
        Argumente für winget upgrade/uninstall. Pakete werden nur über die exakte ID angesprochen.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Update', 'Uninstall')] [string] $Action,
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Source,
        [ValidateSet('User', 'Machine', 'Unknown')] [string] $Scope = 'Unknown',
        # Nur nach gespeicherter Zustimmung des Benutzers (Store-Vereinbarung) für die Quelle „msstore“
        [switch] $StoreAgreementAccepted
    )

    $verb = if ($Action -eq 'Update') { 'upgrade' } else { 'uninstall' }
    $list = [System.Collections.Generic.List[string]]::new()
    $list.AddRange([string[]] @($verb, '--id', $Id, '--exact', '--source', $Source, '--silent'))
    # Der Quelle „msstore“ wird nie still zugestimmt: nur, wenn der Benutzer die Vereinbarung bestätigt hat.
    if ($Source -ne 'msstore' -or $StoreAgreementAccepted) { $list.Add('--accept-source-agreements') }
    $list.Add('--disable-interactivity')
    # Ohne Zustimmung zu Paketlizenzen bricht ein Upgrade ohne Rückfrage ab.
    if ($Action -eq 'Update') { $list.Add('--accept-package-agreements') }
    # Beim Deinstallieren den Bereich festlegen, falls dasselbe Paket für Benutzer und Rechner installiert ist.
    if ($Action -eq 'Uninstall' -and $Scope -ne 'Unknown') { $list.AddRange([string[]] @('--scope', $Scope.ToLowerInvariant())) }
    ConvertTo-ArgumentString $list
}
