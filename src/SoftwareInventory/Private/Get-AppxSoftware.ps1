function Get-AppxSoftware {
    <#
    .SYNOPSIS
        Liefert Store- und MSIX-Apps des aktuellen Benutzers.
    .DESCRIPTION
        Frameworks, Systemkomponenten und nicht entfernbare Pakete werden ausgefiltert.
        Als Name dient der Paketname (z. B. Microsoft.WindowsCalculator); den
        Anzeigenamen ergänzt Merge-SoftwareRecord aus winget, falls vorhanden.
        Sparse Packages (AllowExternalContent) gehören meist zu einem klassischen Programm,
        etwa als Kontextmenü-Erweiterung. Sie erhalten das Flag SparsePackage; Merge-SoftwareRecord
        ordnet sie dem Programm zu, wenn das eindeutig möglich ist.
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
        $manifest = Get-AppxManifestInfo -InstallLocation $pkg.InstallLocation
        # Store-Pakete tragen oft nur eine GUID als Herausgeber; der Klarname steht im Manifest.
        if ($publisher -match '^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$' -and $manifest.PublisherDisplayName) {
            $publisher = $manifest.PublisherDisplayName
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
        if ($manifest.Sparse) {
            $record.Flags = [string[]] @('SparsePackage')
            # Nur für die Zuordnung in Merge-SoftwareRecord; wird dort wieder entfernt.
            $record | Add-Member -NotePropertyName CompanionInfo -NotePropertyValue @{
                DisplayName = $manifest.DisplayName; PublisherDisplayName = $manifest.PublisherDisplayName
            }
        }
        Add-MatchKey -Record $record -Key @(
            "msix:$($pkg.PackageFullName)".ToLowerInvariant()
            "pfn:$($pkg.PackageFamilyName)".ToLowerInvariant()
        )
    }
}

function Get-AppxManifestInfo {
    # Liest aus AppxManifest.xml Anzeige- und Herausgebernamen (ohne ms-resource:-Verweise)
    # und ob es ein Sparse Package ist (uap10:AllowExternalContent).
    param([string] $InstallLocation)
    $info = @{ DisplayName = $null; PublisherDisplayName = $null; Sparse = $false }
    if (-not $InstallLocation) { return $info }
    $manifest = Join-Path $InstallLocation 'AppxManifest.xml'
    try {
        $xml = [xml] (Get-Content -LiteralPath $manifest -Raw -ErrorAction Stop)
        $properties = $xml.DocumentElement.SelectSingleNode("*[local-name()='Properties']")
        if (-not $properties) { return $info }
        foreach ($field in 'DisplayName', 'PublisherDisplayName') {
            $node = $properties.SelectSingleNode("*[local-name()='$field']")
            $value = if ($node) { ConvertTo-NullIfEmpty $node.InnerText }
            if ($value -and $value -notlike 'ms-resource:*') { $info[$field] = $value }
        }
        $external = $properties.SelectSingleNode("*[local-name()='AllowExternalContent']")
        $info.Sparse = [bool] ($external -and $external.InnerText.Trim() -eq 'true')
    }
    catch {
        Write-Verbose "Manifest nicht lesbar: $manifest"
    }
    $info
}

function ConvertFrom-DistinguishedName {
    # "CN=Mozilla Corporation, O=Mozilla Corporation, C=US" -> "Mozilla Corporation"
    param([string] $Value)
    if ($Value -match '(?:^|,\s*)O="?(?<o>[^",]+)') { return $Matches.o.Trim() }
    if ($Value -match '^CN="?(?<cn>[^",]+)') { return $Matches.cn.Trim() }
    ConvertTo-NullIfEmpty $Value
}
