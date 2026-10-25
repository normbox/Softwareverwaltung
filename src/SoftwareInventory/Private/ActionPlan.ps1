# Planung einer Aktion: aktuellen Zustand neu lesen, Methode wählen, Befehl bauen und entscheiden,
# ob Administratorrechte nötig sind. Alles hier läuft ohne Adminrechte und führt nichts aus.
#
# Regeln (siehe docs/AKTIONEN.md):
# - Werte aus dem übergebenen Datensatz werden nie blind übernommen; Registry, Appx und winget
#   werden neu gelesen. Ein veränderter Snapshot kann so keinen fremden Befehl einschleusen.
# - Einträge unter HKCU und Store-Apps laufen immer im aktuellen Benutzer, nie erhöht.
# - Programme mit unbekanntem Bereich (nur in winget bekannt) laufen ohne eigene Erhöhung;
#   winget fordert die UAC bei Bedarf selbst an.
# - Mit Adminrechten wird keine Datei gestartet, die der Benutzer verändern könnte.

$script:UninstallMethods = @('Winget', 'Msi', 'Appx', 'QuietUninstallString', 'UninstallString')
$script:MsiExecutable = Join-Path ([Environment]::GetFolderPath('System')) 'msiexec.exe'

function Get-ActionRecord {
    # Akzeptiert einen SoftwareRecord oder ein Objekt mit .Record (SecurityRating, UpdateStatus).
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject.PSObject.Properties['Record'] -and $InputObject.Record) { return $InputObject.Record }
    $InputObject
}

function Get-RecordValue {
    # Liest ein Feld eines Datensatzes; fehlende Felder (z. B. bei älteren Snapshots) ergeben $null.
    param($Record, [string] $Name)
    $p = $Record.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Resolve-UninstallKeyLocation {
    <#
    .SYNOPSIS
        Prüft, ob ein Registry-Pfad ein Uninstall-Schlüssel ist, und liefert dessen Bereich.
    .OUTPUTS
        @{ Path; Scope } oder $null, wenn der Pfad nicht unter einem bekannten Uninstall-Zweig liegt.
    #>
    param([string] $RegistryKey)
    if (-not $RegistryKey) { return $null }
    foreach ($loc in Get-DefaultUninstallLocation) {
        $prefix = $loc.Path.TrimEnd('\') + '\'
        if (-not $RegistryKey.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $name = $RegistryKey.Substring($prefix.Length)
        if (-not $name -or $name.Contains('\')) { return $null }
        return @{ Path = $prefix + $name; Scope = $loc.Scope; KeyName = $name }
    }
    $null
}

function Get-AppxPackageByFamily {
    param([string] $PackageFamilyName)
    try {
        Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop | Where-Object PackageFamilyName -eq $PackageFamilyName | Select-Object -First 1
    }
    catch {
        Write-Verbose "Store-Apps nicht abfragbar: $_"
        $null
    }
}

function Get-WingetInstalledVersion {
    # Installierte Version laut winget, oder $null (nicht installiert oder Modul fehlt).
    param([string] $Id)
    if (-not (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue)) { return $null }
    try {
        $pkg = Get-WinGetPackage -Id $Id -MatchOption Equals -ErrorAction Stop | Select-Object -First 1
        if ($pkg) { [string] $pkg.InstalledVersion }
    }
    catch {
        Write-Verbose "winget-Abfrage für '$Id' fehlgeschlagen: $_"
        $null
    }
}

function Get-InstalledState {
    <#
    .SYNOPSIS
        Liest den aktuellen Zustand eines Programms neu ein (vor und nach einer Aktion).
    #>
    param([Parameter(Mandatory)] $Record)

    $state = [ordered]@{
        Present              = $false
        Version              = $null
        Scope                = 'Unknown'
        RegistryKey          = $null
        ProductCode          = $null
        UninstallString      = $null
        QuietUninstallString = $null
        UrlUpdateInfo        = $null
        UrlInfoAbout         = $null
        PackageFullName      = $null
        WingetVersion        = $null
        Identity             = $null   # Registry, Appx, Winget oder $null
    }

    $location = Resolve-UninstallKeyLocation (Get-RecordValue $Record 'RegistryKey')
    $familyName = Get-RecordValue $Record 'PackageFamilyName'
    $wingetId = Get-RecordValue $Record 'WingetId'

    if ($location) {
        $state.Identity = 'Registry'
        $state.Scope = $location.Scope
        $key = Get-Item -LiteralPath $location.Path -ErrorAction SilentlyContinue
        if ($key) {
            $state.Present = $true
            $state.RegistryKey = $location.Path
            $state.Version = ConvertTo-NullIfEmpty $key.GetValue('DisplayVersion')
            $state.UninstallString = ConvertTo-NullIfEmpty $key.GetValue('UninstallString')
            $state.QuietUninstallString = ConvertTo-NullIfEmpty $key.GetValue('QuietUninstallString')
            $state.UrlUpdateInfo = ConvertTo-NullIfEmpty $key.GetValue('URLUpdateInfo')
            $state.UrlInfoAbout = ConvertTo-NullIfEmpty $key.GetValue('URLInfoAbout')
            # Echte Produkt-ID nur bei Windows-Installer-Einträgen, deren Schlüsselname die GUID ist.
            if ($key.GetValue('WindowsInstaller') -eq 1 -and $location.KeyName -match '^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$') {
                $state.ProductCode = $location.KeyName.ToUpperInvariant()
            }
        }
    }
    elseif ($familyName) {
        $state.Identity = 'Appx'
        $state.Scope = 'User'
        $pkg = Get-AppxPackageByFamily $familyName
        if ($pkg) {
            $state.Present = $true
            $state.Version = [string] $pkg.Version
            $state.PackageFullName = $pkg.PackageFullName
        }
    }

    if ($wingetId) {
        $state.WingetVersion = Get-WingetInstalledVersion $wingetId
        if (-not $state.Identity) {
            $state.Identity = 'Winget'
            $state.Present = [bool] $state.WingetVersion
            $state.Version = $state.WingetVersion
        }
    }
    [pscustomobject] $state
}

function Get-VendorUrl {
    # Herstellerlink für manuelle Updates: Registry, sonst GitHub-Releases aus dem Katalog. Nur http(s).
    param($Record, $State)
    $candidates = @($State.UrlUpdateInfo, $State.UrlInfoAbout)
    $match = Find-CatalogEntry -Record $Record -Catalog (Get-SoftwareCatalog)
    if ($match -and $match.Entry.PSObject.Properties['GitHub'] -and $match.Entry.GitHub.Repository) {
        $candidates += "https://github.com/$($match.Entry.GitHub.Repository)/releases"
    }
    foreach ($url in $candidates) {
        $uri = $null
        if ($url -and [uri]::TryCreate($url, [UriKind]::Absolute, [ref] $uri) -and $uri.Scheme -in 'https', 'http') { return $uri.AbsoluteUri }
    }
    $null
}

function Get-AvailableUninstallMethod {
    param($Record, $State)
    $wingetId = Get-RecordValue $Record 'WingetId'
    $wingetSource = Get-RecordValue $Record 'WingetSource'
    $available = foreach ($m in $script:UninstallMethods) {
        $ok = switch ($m) {
            'Winget' { [bool] ($wingetId -and $wingetSource) }
            'Msi' { [bool] $State.ProductCode }
            'Appx' { [bool] $State.PackageFullName }
            'QuietUninstallString' { [bool] $State.QuietUninstallString }
            'UninstallString' { [bool] $State.UninstallString }
        }
        if ($ok) { $m }
    }
    @($available)
}

function New-ActionPlan {
    <#
    .SYNOPSIS
        Plant eine Aktion: Methode, Programm, Argumente, Adminrechte. Führt nichts aus.
    .DESCRIPTION
        Ist die Aktion nicht ausführbar, ist Result gesetzt (NotInstalled, Unsupported,
        ManualUpdateRequired) und Message nennt den Grund.
    #>
    param(
        [Parameter(Mandatory)] [ValidateSet('Update', 'Uninstall')] [string] $Action,
        [Parameter(Mandatory)] $Record,
        [ValidateSet('Auto', 'Winget', 'Msi', 'Appx', 'QuietUninstallString', 'UninstallString')] [string] $Method = 'Auto',
        [bool] $RestorePoint = $false
    )

    $state = Get-InstalledState -Record $Record
    $plan = [ordered]@{
        PSTypeName      = 'SoftwareInventory.ActionPlan'
        ActionId        = [guid]::NewGuid().ToString()
        Action          = $Action
        Name            = $Record.Name
        WingetId        = Get-RecordValue $Record 'WingetId'
        WingetSource    = Get-RecordValue $Record 'WingetSource'
        RegistryKey     = $state.RegistryKey
        ProductCode     = $state.ProductCode
        PackageFullName = $state.PackageFullName
        Scope           = $state.Scope
        Method          = 'None'
        FilePath        = $null
        Arguments       = $null
        CommandLine     = $null
        Elevated        = $false
        MsiLog          = $false
        RestorePoint    = $RestorePoint
        Result          = $null
        Message         = $null
        NextMethod      = $null
        VendorUrl       = $null
        State           = $state
    }
    $finish = { param($Result, $Message) $plan.Result = $Result; $plan.Message = $Message; [pscustomobject] $plan }

    if (-not $state.Present) {
        return & $finish 'NotInstalled' 'Das Programm ist nicht (mehr) installiert; es wurde nichts ausgeführt.'
    }

    if ($Action -eq 'Update') {
        if (-not ($plan.WingetId -and $plan.WingetSource)) {
            $plan.VendorUrl = Get-VendorUrl -Record $Record -State $state
            $hint = if ($plan.VendorUrl) { "Update bitte manuell über den Hersteller: $($plan.VendorUrl)" } else { 'Update bitte manuell über den Hersteller; kein Link bekannt.' }
            $plan.Method = 'VendorLink'
            return & $finish 'ManualUpdateRequired' "Kein winget-Paket bekannt. $hint"
        }
        if ($Method -notin 'Auto', 'Winget') { return & $finish 'Unsupported' 'Aktualisieren geht nur über winget.' }
        $chosen = 'Winget'
        $available = @('Winget')
    }
    else {
        $available = @(Get-AvailableUninstallMethod -Record $Record -State $state)
        if (-not $available) { return & $finish 'Unsupported' 'Keine Deinstallationsmethode bekannt (kein winget-Paket, kein MSI, keine Store-App, kein Deinstallationsbefehl).' }
        $chosen = if ($Method -eq 'Auto') { $available[0] } else { $Method }
        if ($chosen -notin $available) { return & $finish 'Unsupported' "Methode $chosen ist für dieses Programm nicht verfügbar (verfügbar: $($available -join ', '))." }
    }
    $plan.Method = $chosen
    $index = [array]::IndexOf($available, $chosen)
    if ($index -ge 0 -and $index + 1 -lt $available.Count) { $plan.NextMethod = $available[$index + 1] }

    switch ($chosen) {
        'Winget' {
            if ($plan.WingetId -notmatch '^[\w.+-]+$' -or $plan.WingetSource -notmatch '^[\w.-]+$') {
                return & $finish 'Unsupported' 'Ungültige winget-ID oder -Quelle.'
            }
            $winget = Get-WingetExecutable
            if (-not $winget) { return & $finish 'Unsupported' 'winget wurde nicht gefunden (App Installer fehlt).' }
            $plan.FilePath = $winget
            $plan.Arguments = Get-WingetArgument -Action $Action -Id $plan.WingetId -Source $plan.WingetSource -Scope $state.Scope
            # Unbekannter Bereich: keine eigene Erhöhung, winget fordert sie bei Bedarf selbst an.
            $plan.Elevated = $state.Scope -eq 'Machine'
        }
        'Msi' {
            $plan.FilePath = $script:MsiExecutable
            $plan.Arguments = "/x $($state.ProductCode) /qn /norestart"
            $plan.MsiLog = $true
            $plan.Elevated = $state.Scope -eq 'Machine'
        }
        'Appx' {
            $plan.CommandLine = "Remove-AppxPackage -Package $($state.PackageFullName)"
            $plan.Elevated = $false
        }
        default {
            $command = Resolve-UninstallCommand $state.$chosen
            if ($command.Error) { return & $finish 'Unsupported' $command.Error }
            $plan.FilePath = $command.FilePath
            $plan.Arguments = $command.Arguments
            # HKCU-Befehle kann jeder Prozess ohne Adminrechte schreiben: nie erhöht ausführen.
            $plan.Elevated = $state.Scope -eq 'Machine'
            if ($plan.Elevated -and (Test-UserWritablePath $command.FilePath)) {
                return & $finish 'Unsupported' "Das Deinstallationsprogramm liegt an einem für Benutzer beschreibbaren Ort ($($command.FilePath)) und wird aus Sicherheitsgründen nicht mit Administratorrechten gestartet. Bitte manuell deinstallieren."
            }
        }
    }
    if (-not $plan.CommandLine) {
        $display = if ($plan.MsiLog) { "$($plan.Arguments) /l*v <Installer-Log>" } else { $plan.Arguments }
        $plan.CommandLine = Format-CommandLine -FilePath $plan.FilePath -Arguments $display
    }
    [pscustomobject] $plan
}
