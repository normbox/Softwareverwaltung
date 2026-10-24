function Get-AppxSoftware {
    <#
    .SYNOPSIS
        Liefert Store- und MSIX-Apps des aktuellen Benutzers.
    .DESCRIPTION
        Frameworks, Systemkomponenten und nicht entfernbare Pakete werden ausgefiltert.
        Als Name dient der Paketname (z. B. Microsoft.WindowsCalculator); den
        Anzeigenamen ergänzt Merge-SoftwareRecord aus winget, falls vorhanden.
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param()

    try {
        $packages = @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop)
    }
    catch {
        Write-Warning "Store-Apps nicht verfügbar: $_"
        return
    }

    foreach ($pkg in $packages) {
        if ($pkg.IsFramework -or $pkg.NonRemovable -or [string] $pkg.SignatureKind -eq 'System') { continue }

        $publisher = ConvertFrom-DistinguishedName $pkg.Publisher
        # Store-Pakete tragen oft nur eine GUID als Herausgeber; der Klarname steht im Manifest.
        if ($publisher -match '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$') {
            $displayName = Get-AppxPublisherDisplayName -InstallLocation $pkg.InstallLocation
            if ($displayName) { $publisher = $displayName }
        }

        $record = New-SoftwareRecord -Name $pkg.Name -Source Appx -Property @{
            Publisher         = $publisher
            Version           = [string] $pkg.Version
            InstallType       = 'MSIX'
            Scope             = 'User'
            Architecture      = [string] $pkg.Architecture
            PackageFullName   = $pkg.PackageFullName
            PackageFamilyName = $pkg.PackageFamilyName
            InstallLocation   = $pkg.InstallLocation
        }
        Add-MatchKey -Record $record -Key @(
            "msix:$($pkg.PackageFullName)".ToLowerInvariant()
            "pfn:$($pkg.PackageFamilyName)".ToLowerInvariant()
        )
    }
}

function Get-AppxPublisherDisplayName {
    # Liest PublisherDisplayName aus AppxManifest.xml; Ressourcenverweise (ms-resource:) werden ignoriert.
    param([string] $InstallLocation)
    if (-not $InstallLocation) { return }
    $manifest = Join-Path $InstallLocation 'AppxManifest.xml'
    try {
        $xml = [xml] (Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop)
        $name = ConvertTo-NullIfEmpty $xml.Package.Properties.PublisherDisplayName
        if ($name -and $name -notlike 'ms-resource:*') { $name }
    }
    catch {
        Write-Verbose "Manifest nicht lesbar: $manifest"
    }
}

function ConvertFrom-DistinguishedName {
    # "CN=Mozilla Corporation, O=Mozilla Corporation, C=US" -> "Mozilla Corporation"
    param([string] $Value)
    if ($Value -match '(?:^|,\s*)O="?(?<o>[^",]+)') { return $Matches.o.Trim() }
    if ($Value -match '^CN="?(?<cn>[^",]+)') { return $Matches.cn.Trim() }
    ConvertTo-NullIfEmpty $Value
}
