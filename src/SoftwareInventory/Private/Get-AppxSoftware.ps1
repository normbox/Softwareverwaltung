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

        $record = New-SoftwareRecord -Name $pkg.Name -Source Appx -Property @{
            Publisher         = ConvertFrom-DistinguishedName $pkg.Publisher
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

function ConvertFrom-DistinguishedName {
    # "CN=Mozilla Corporation, O=Mozilla Corporation, C=US" -> "Mozilla Corporation"
    param([string] $Value)
    if ($Value -match '(?:^|,\s*)O="?(?<o>[^",]+)') { return $Matches.o.Trim() }
    if ($Value -match '^CN="?(?<cn>[^",]+)') { return $Matches.cn.Trim() }
    ConvertTo-NullIfEmpty $Value
}
