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
        @{ Path; Scope; KeyName; Architecture } oder $null, wenn der Pfad nicht unter einem bekannten
        Uninstall-Zweig liegt. Architecture: X86 für WOW6432Node, sonst die des Systems (z. B. X64).
    #>
    param([string] $RegistryKey)
    if (-not $RegistryKey) { return $null }
    foreach ($loc in Get-DefaultUninstallLocation) {
        $prefix = $loc.Path.TrimEnd('\') + '\'
        if (-not $RegistryKey.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $name = $RegistryKey.Substring($prefix.Length)
        if (-not $name -or $name.Contains('\')) { return $null }
        $architecture = if ($loc.Architecture) { $loc.Architecture } else { [string] [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture }
        return @{ Path = $prefix + $name; Scope = $loc.Scope; KeyName = $name; Architecture = $architecture }
    }
    $null
}

function Get-WingetLocalId {
    <#
    .SYNOPSIS
        Lokale Kennung, unter der winget einen Registry-Eintrag führt: ARP\<User|Machine>\<Architektur>\<Schlüssel>.
    .DESCRIPTION
        winget vergleicht „--id … --exact“ mit dieser Kennung, nicht mit der angezeigten Katalog-ID. Bei
        portablen winget-Paketen (z. B. Gyan.FFmpeg) unterscheiden sich beide; dann findet nur sie das Paket.
    #>
    param($Record)
    $location = Resolve-UninstallKeyLocation (Get-RecordValue $Record 'RegistryKey')
    if (-not $location) { return $null }
    "ARP\$($location.Scope)\$($location.Architecture)\$($location.KeyName)"
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
    # Mit Quelle, sonst scheitert die Abfrage ganz, wenn eine andere Quelle (z. B. msstore) gestört ist.
    param([string] $Id, [string] $Source)
    if (Get-WingetClientProblem) { return $null }
    $query = @{ Id = $Id; MatchOption = 'Equals' }
    if ($Source) { $query.Source = $Source }
    try {
        $pkg = Get-WinGetPackage @query -ErrorAction Stop | Select-Object -First 1
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
        $state.WingetVersion = Get-WingetInstalledVersion $wingetId (Get-RecordValue $Record 'WingetSource')
        if ($state.Identity -eq 'Registry' -and -not $state.Present -and $state.WingetVersion) {
            # Schlüssel weg, Paket laut winget aber da: typisch für MSI-Updates mit neuem ProductCode.
            $state.Present = $true
            $state.Version = $state.WingetVersion
        }
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
        return & $finish 'NotInstalled' (New-InventoryMessage PlanNotInstalled)
    }

    if ($Action -eq 'Update') {
        if (-not ($plan.WingetId -and $plan.WingetSource)) {
            $plan.VendorUrl = Get-VendorUrl -Record $Record -State $state
            $hint = if ($plan.VendorUrl) { New-InventoryMessage PlanManualUpdateLink $plan.VendorUrl } else { New-InventoryMessage PlanManualUpdateNoLink }
            $plan.Method = 'VendorLink'
            return & $finish 'ManualUpdateRequired' $hint
        }
        if ($Method -notin 'Auto', 'Winget') { return & $finish 'Unsupported' (New-InventoryMessage PlanUpdateOnlyWinget) }
        $chosen = 'Winget'
        $available = @('Winget')
    }
    else {
        $available = @(Get-AvailableUninstallMethod -Record $Record -State $state)
        if (-not $available) { return & $finish 'Unsupported' (New-InventoryMessage PlanNoUninstallMethod) }
        $chosen = if ($Method -eq 'Auto') { $available[0] } else { $Method }
        if ($chosen -notin $available) { return & $finish 'Unsupported' (New-InventoryMessage PlanMethodNotAvailable $chosen, ($available -join ', ')) }
    }
    $plan.Method = $chosen
    $index = [array]::IndexOf($available, $chosen)
    if ($index -ge 0 -and $index + 1 -lt $available.Count) { $plan.NextMethod = $available[$index + 1] }

    switch ($chosen) {
        'Winget' {
            if ($plan.WingetId -notmatch '^[\w.+-]+$' -or $plan.WingetSource -notmatch '^[\w.-]+$') {
                return & $finish 'Unsupported' (New-InventoryMessage PlanInvalidWingetId)
            }
            $winget = Get-WingetExecutable
            if (-not $winget) { return & $finish 'Unsupported' (New-InventoryMessage PlanWingetNotFound) }
            # Store-Pakete erst nach bestätigter Store-Vereinbarung (einmal, in der App mit Rückfrage).
            $storeAccepted = Test-StoreAgreementAccepted
            if ($plan.WingetSource -eq 'msstore' -and -not $storeAccepted) {
                return & $finish 'StoreAgreementRequired' (New-InventoryMessage StoreAgreementRequired)
            }
            # Findet winget das Paket mit „--exact“ nur über die lokale Kennung, wird diese verwendet;
            # findet es das Paket gar nicht genau, wird nichts ausgeführt (nie ohne „--exact“).
            $target = Resolve-WingetTargetId -Record $Record -Id $plan.WingetId -Source $plan.WingetSource
            if (-not $target) {
                if ($Action -eq 'Update') {
                    $plan.Method = 'VendorLink'
                    $plan.VendorUrl = Get-VendorUrl -Record $Record -State $state
                    $message = if ($plan.VendorUrl) { New-InventoryMessage PlanWingetExactNotFoundLink $plan.WingetId, $plan.VendorUrl } else { New-InventoryMessage PlanWingetExactNotFound $plan.WingetId }
                    return & $finish 'ManualUpdateRequired' $message
                }
                return & $finish 'Unsupported' (New-InventoryMessage PlanWingetExactNotFoundUninstall $plan.WingetId)
            }
            $plan.FilePath = $winget
            $plan.Arguments = Get-WingetArgument -Action $Action -Id $target.Id -Source $plan.WingetSource -Scope $state.Scope -StoreAgreementAccepted:$storeAccepted
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
                return & $finish 'Unsupported' (New-InventoryMessage PlanUninstallerUserWritable $command.FilePath)
            }
        }
    }
    if (-not $plan.CommandLine) {
        $display = if ($plan.MsiLog) { "$($plan.Arguments) /l*v <Installer-Log>" } else { $plan.Arguments }
        $plan.CommandLine = Format-CommandLine -FilePath $plan.FilePath -Arguments $display
    }
    [pscustomobject] $plan
}
