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
