# Erkennt winget-Pakete, bei denen winget vor dem Update die alte Version entfernt
# (UpgradeBehavior: uninstallPrevious). Weder „winget show“ noch die COM-Schnittstelle nennen das Feld,
# es steht nur im Manifest. Der Abruf ist ein eigener Dienst und standardmäßig aus; ein fester Katalogeintrag
# warnt auch ohne ihn. Nicht ermittelbar heißt: keine Warnung, die Aktion wird nie blockiert.

$script:WingetManifestBase = 'https://raw.githubusercontent.com/microsoft/winget-pkgs/master/manifests'
$script:WingetManifestMaxAgeDays = 30
$script:WingetManifestTimeoutSeconds = 5

function Get-WingetManifestUri {
    # manifests/<erster Buchstabe klein>/<ID, Punkte als Ordner>/<Version>/<ID>.installer.yaml
    param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Version)
    $folders = ($Id -split '\.' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $file = [uri]::EscapeDataString("$Id.installer.yaml")
    "$script:WingetManifestBase/$($Id.Substring(0, 1).ToLowerInvariant())/$folders/$([uri]::EscapeDataString($Version))/$file"
}

function ConvertTo-WingetManifestCacheContent {
    # Aus der YAML-Datei nur das eine Feld behalten, oben oder je Eintrag unter „Installers“.
    param([string] $Content)
    $found = $Content -match '(?im)^[ \t]*(-[ \t]+)?UpgradeBehavior:[ \t]*[''"]?uninstallPrevious[''"]?[ \t]*(#.*)?\r?$'
    [pscustomobject] @{ UninstallsPrevious = [bool] $found } | ConvertTo-Json -Compress
}

function Test-WingetUninstallsPrevious {
    <#
    .SYNOPSIS
        Entfernt winget bei diesem Update vorher die alte Version?
    .DESCRIPTION
        Zuerst der Katalog (ohne Netz), dann das Manifest der Zielversion, wenn der Dienst WingetManifest an ist.
        Kurze Zeitgrenze, denn der Abruf läuft, während der Bestätigungsdialog wartet.
    #>
    param(
        [Parameter(Mandatory)] $Record,
        [Parameter(Mandatory)] [string] $Id,
        [string] $Source,
        $Setting = (Read-InventorySetting)
    )
    try {
        $match = Find-CatalogEntry -Record $Record -Catalog (Get-SoftwareCatalog)
        if ($match -and (Get-CatalogValue $match.Entry 'WingetUninstallsPrevious')) { return $true }

        $version = Get-RecordValue $Record 'AvailableVersion'
        if ($Source -ne 'winget' -or -not $version -or $version -notmatch '^[\w.+-]+$') { return $false }
        if (-not (Test-ServiceEnabled -Name WingetManifest -Setting $Setting)) { return $false }
        $data = Invoke-ServiceRequest -Service WingetManifest -Uri (Get-WingetManifestUri -Id $Id -Version $version) -CacheKey "$Id/$version" `
            -MaxAge ([timespan]::FromDays($script:WingetManifestMaxAgeDays)) -TimeoutSeconds $script:WingetManifestTimeoutSeconds -NoRetryWait -Setting $Setting
        [bool] $data.UninstallsPrevious
    }
    catch {
        Write-Verbose "winget-Manifest für '$Id' nicht abrufbar: $_"
        $false
    }
}
