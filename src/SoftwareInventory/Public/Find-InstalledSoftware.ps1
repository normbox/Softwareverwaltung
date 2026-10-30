function Find-InstalledSoftware {
    <#
    .SYNOPSIS
        Liest das Inventar neu und liefert das Programm, das zu einem früheren Datensatz gehört.
    .DESCRIPTION
        Für die Prüfung nach einer Aktion: Gleich ist ein Programm, wenn Registry-Schlüssel,
        winget-ID oder PackageFamilyName übereinstimmen. So wird ein Programm auch nach einem
        MSI-Update mit neuem ProductCode (neuer Registry-Schlüssel) über die winget-ID wiedergefunden.
        Ist es nicht mehr installiert, kommt nichts zurück. Gelesen werden nur die aktivierten Quellen.
        Portable Programme (ohne Registry-Schlüssel, winget-ID und PackageFamilyName) findet das Inventar
        nicht; für sie wird die Datei unter FilePath neu gelesen (Version, Signatur), die Nutzungsspuren
        bleiben aus dem früheren Datensatz. Fehlt die Datei, kommt nichts zurück; ist ihr Laufwerk gerade
        nicht verbunden (z. B. USB-Stick), kommt der frühere Datensatz unverändert zurück.
    .PARAMETER Reference
        Datensatz aus Get-SoftwareInventory oder ein Objekt mit .Record (z. B. aus Get-SecurityRating).
    .EXAMPLE
        $rating | Find-InstalledSoftware | Get-SecurityRating
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $Reference
    )

    process {
        $record = Get-ActionRecord $Reference
        if (-not $record) { return }
        $keys = Get-SameSoftwareKey $record
        if (-not $keys) {
            $file = Get-RecordValue $record 'FilePath'
            if ($file) { Find-PortableAgain -Record $record -Path $file }
            return
        }
        Get-SoftwareInventory | Where-Object {
            $candidate = Get-SameSoftwareKey $_
            [bool] ($candidate | Where-Object { $_ -in $keys })
        }
    }
}

function Find-PortableAgain {
    # Portables Programm erneut lesen: aus der Datei, nicht über eine neue Suche (die liefe über alle Spuren und Laufwerke).
    param($Record, [string] $Path)
    if (-not (Test-PathRootReachable $Path)) { return $Record }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $setting = Read-InventorySetting
    try { $info = Get-ExecutableInfo -Path $Path -SkipHash:(-not $setting.FileScan.ComputeHash) }
    catch { Write-Verbose "Nicht lesbar: $Path"; return $Record }
    $info | Add-Member -Force -NotePropertyMembers @{
        Evidence = [string[]] @(Get-RecordValue $Record 'Evidence'); LastRun = Get-RecordValue $Record 'LastRun'; RunCount = Get-RecordValue $Record 'RunCount'
    }
    $fresh = ConvertTo-PortableRecord -File @($info)
    # Hilfsfelder der Suche entfernen; „mehrere Versionen“ lässt sich nur über alle Ordner bestimmen und bleibt.
    foreach ($name in 'CopyKey', 'HasProductName') { $fresh.PSObject.Properties.Remove($name) }
    if (@(Get-RecordValue $Record 'Flags') -contains 'MultipleVersions') { $fresh.Flags = [string[]] @(@($fresh.Flags) + 'MultipleVersions' | Where-Object { $_ }) }
    $fresh
}

function Get-SameSoftwareKey {
    # Schlüssel, über die zwei Datensätze als dasselbe Programm gelten (ohne Name, der oft die Version enthält).
    param($Record)
    $prefix = @{ RegistryKey = 'reg'; WingetId = 'winget'; PackageFamilyName = 'pfn' }
    foreach ($name in 'RegistryKey', 'WingetId', 'PackageFamilyName') {
        $value = Get-RecordValue $Record $name
        if ($value) { "$($prefix[$name]):$value".ToLowerInvariant() }
    }
}
