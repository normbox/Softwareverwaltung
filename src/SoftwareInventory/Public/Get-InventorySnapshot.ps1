function Get-InventorySnapshot {
    <#
    .SYNOPSIS
        Lädt gespeicherte Inventare, neueste zuerst.
    .PARAMETER Latest
        Nur die neuesten N Snapshots laden.
    .PARAMETER LiteralPath
        Einzelne Snapshot-Datei laden.
    .EXAMPLE
        Get-InventorySnapshot -Latest 1 | Select-Object -ExpandProperty Records
    #>
    [CmdletBinding(DefaultParameterSetName = 'Directory')]
    [OutputType('SoftwareInventory.Snapshot')]
    param(
        [Parameter(ParameterSetName = 'Directory')]
        [string] $Directory = (Get-DefaultSnapshotDirectory),

        [Parameter(ParameterSetName = 'Directory')]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Latest,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string[]] $LiteralPath
    )

    $files = if ($PSCmdlet.ParameterSetName -eq 'File') {
        $LiteralPath
    }
    elseif (Test-Path -LiteralPath $Directory) {
        $all = Get-ChildItem -LiteralPath $Directory -Filter '*.json' | Sort-Object Name -Descending
        if ($Latest) { $all = $all | Select-Object -First $Latest }
        $all.FullName
    }

    foreach ($file in $files) {
        $data = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -DateKind String
        if ($data.SchemaVersion -gt $script:SnapshotSchemaVersion) {
            Write-Warning "Snapshot '$file' hat neueres Schema $($data.SchemaVersion) und wird übersprungen."
            continue
        }
        foreach ($record in $data.Records) { $record.PSObject.TypeNames.Insert(0, 'SoftwareInventory.SoftwareRecord') }

        [pscustomobject] @{
            PSTypeName    = 'SoftwareInventory.Snapshot'
            CreatedAt     = [datetime]::Parse($data.CreatedAt, [cultureinfo]::InvariantCulture, 'RoundtripKind')
            Path          = (Resolve-Path -LiteralPath $file).ProviderPath
            SchemaVersion = $data.SchemaVersion
            Count         = @($data.Records).Count
            Records       = @($data.Records)
        }
    }
}
