function Find-InstalledSoftware {
    <#
    .SYNOPSIS
        Liest das Inventar neu und liefert das Programm, das zu einem früheren Datensatz gehört.
    .DESCRIPTION
        Für die Prüfung nach einer Aktion: Gleich ist ein Programm, wenn Registry-Schlüssel,
        winget-ID oder PackageFamilyName übereinstimmen. So wird ein Programm auch nach einem
        MSI-Update mit neuem ProductCode (neuer Registry-Schlüssel) über die winget-ID wiedergefunden.
        Ist es nicht mehr installiert, kommt nichts zurück. Gelesen werden nur die aktivierten Quellen.
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
        if (-not $keys) { return }
        Get-SoftwareInventory | Where-Object {
            $candidate = Get-SameSoftwareKey $_
            [bool] ($candidate | Where-Object { $_ -in $keys })
        }
    }
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
