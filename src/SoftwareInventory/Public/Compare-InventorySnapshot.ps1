function Compare-InventorySnapshot {
    <#
    .SYNOPSIS
        Zeigt Unterschiede zwischen zwei Inventaren: hinzugekommen, entfernt, Version geändert.
    .DESCRIPTION
        Ohne Parameter werden die beiden neuesten gespeicherten Snapshots verglichen.
        Reference/Difference nehmen Snapshots (Get-InventorySnapshot) oder
        Datensätze (Get-SoftwareInventory) entgegen.
    .EXAMPLE
        Compare-InventorySnapshot
    .EXAMPLE
        Compare-InventorySnapshot -Reference (Get-InventorySnapshot -Latest 1) -Difference (Get-SoftwareInventory)
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.Change')]
    param(
        [object[]] $Reference,
        [object[]] $Difference
    )

    if (-not $PSBoundParameters.ContainsKey('Reference') -and -not $PSBoundParameters.ContainsKey('Difference')) {
        $latest = @(Get-InventorySnapshot -Latest 2)
        if ($latest.Count -lt 2) {
            Write-Warning 'Für einen Vergleich werden mindestens zwei gespeicherte Snapshots benötigt.'
            return
        }
        $Difference = $latest[0]
        $Reference = $latest[1]
    }

    $old = ConvertTo-RecordIndex $Reference
    $new = ConvertTo-RecordIndex $Difference

    foreach ($id in $new.Keys) {
        $n = $new[$id]
        if (-not $old.Contains($id)) {
            New-InventoryChange -Change Added -Old $null -New $n
        }
        elseif ($old[$id].Version -ne $n.Version) {
            New-InventoryChange -Change VersionChanged -Old $old[$id] -New $n
        }
    }
    foreach ($id in $old.Keys) {
        if (-not $new.Contains($id)) {
            New-InventoryChange -Change Removed -Old $old[$id] -New $null
        }
    }
}

function ConvertTo-RecordIndex {
    param([object[]] $InputObject)
    $records = foreach ($item in $InputObject) {
        if ($item.PSObject.TypeNames -contains 'SoftwareInventory.Snapshot') { $item.Records } else { $item }
    }
    $index = [ordered]@{}
    foreach ($r in $records) {
        if ($null -ne $r) { $index[(Get-RecordIdentity $r)] = $r }
    }
    $index
}

function New-InventoryChange {
    param([string] $Change, $Old, $New)
    $record = if ($New) { $New } else { $Old }
    [pscustomobject] @{
        PSTypeName = 'SoftwareInventory.Change'
        Change     = $Change
        Name       = $record.Name
        OldVersion = if ($Old) { $Old.Version } else { $null }
        NewVersion = if ($New) { $New.Version } else { $null }
        Record     = $record
    }
}
