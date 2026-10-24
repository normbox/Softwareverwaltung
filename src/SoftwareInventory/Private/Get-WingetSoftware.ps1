function Get-WingetPackageData {
    <#
    .SYNOPSIS
        Liest installierte Pakete über Microsoft.WinGet.Client als einfache Objekte.
    .DESCRIPTION
        Kapselt den Zugriff auf das WinGet-Modul, damit Tests ihn ersetzen können.
        ProductCodes/PackageFamilyNames der installierten Version stehen nur im
        internen COM-Objekt (CatalogPackageCOM); fehlt es, bleiben sie leer.
    #>
    [CmdletBinding()]
    param()

    $flags = [System.Reflection.BindingFlags] 'Public, NonPublic, Instance'

    foreach ($pkg in Get-WinGetPackage -ErrorAction Stop) {
        $codes = @()
        $families = @()
        try {
            $com = $pkg.GetType().GetProperty('CatalogPackageCOM', $flags).GetValue($pkg)
            $codes = @($com.InstalledVersion.ProductCodes)
            $families = @($com.InstalledVersion.PackageFamilyNames)
        }
        catch {
            Write-Verbose "Keine Zuordnungsdaten für '$($pkg.Id)': $_"
        }

        [pscustomobject] @{
            Name               = $pkg.Name
            Id                 = $pkg.Id
            Source             = $pkg.Source
            InstalledVersion   = $pkg.InstalledVersion
            AvailableVersion   = if ($pkg.IsUpdateAvailable) { @($pkg.AvailableVersions)[0] } else { $null }
            ProductCodes       = [string[]] $codes
            PackageFamilyNames = [string[]] $families
        }
    }
}

function Get-WingetSoftware {
    <#
    .SYNOPSIS
        Liefert Inventar-Datensätze aus winget.
    .DESCRIPTION
        winget kennt neben Katalogpaketen (z. B. 7zip.7zip) auch reine Registry-
        Einträge (ARP\...) und MSIX-Pakete (MSIX\...). Diese dienen nur dem Abgleich
        mit den anderen Quellen; eine echte winget-ID haben nur Katalogpakete.
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param()

    if (-not (Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue)) {
        Write-Warning 'winget-Daten nicht verfügbar: Modul Microsoft.WinGet.Client ist nicht installiert.'
        return
    }

    try {
        $packages = @(Get-WingetPackageData)
    }
    catch {
        Write-Warning "winget-Daten nicht verfügbar: $_"
        return
    }

    foreach ($pkg in $packages) {
        $keys = [System.Collections.Generic.List[string]]::new()
        $property = @{ Version = ConvertTo-NullIfEmpty $pkg.InstalledVersion }

        if ($pkg.Id -match '^ARP\\(?<scope>Machine|User)\\(?<arch>[^\\]+)\\(?<key>.+)$') {
            $keys.Add("arp:$($Matches.scope):$($Matches.key)".ToLowerInvariant())
        }
        elseif ($pkg.Id -match '^MSIX\\(?<full>.+)$') {
            $keys.Add("msix:$($Matches.full)".ToLowerInvariant())
        }
        else {
            $property.WingetId = $pkg.Id
            $property.WingetSource = ConvertTo-NullIfEmpty $pkg.Source
            $property.AvailableVersion = ConvertTo-NullIfEmpty $pkg.AvailableVersion
            foreach ($code in $pkg.ProductCodes) { if ($code) { $keys.Add("arp:$code".ToLowerInvariant()) } }
            foreach ($pfn in $pkg.PackageFamilyNames) { if ($pfn) { $keys.Add("pfn:$pfn".ToLowerInvariant()) } }
        }

        $record = New-SoftwareRecord -Name $pkg.Name -Source Winget -Property $property
        Add-MatchKey -Record $record -Key $keys
    }
}

function Add-MatchKey {
    # Hängt Abgleichschlüssel an einen Datensatz; Merge-SoftwareRecord entfernt sie wieder.
    param($Record, [string[]] $Key)
    $Record | Add-Member -NotePropertyName MatchKeys -NotePropertyValue ([string[]] @($Key)) -PassThru
}
