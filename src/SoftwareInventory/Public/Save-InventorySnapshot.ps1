function Save-InventorySnapshot {
    <#
    .SYNOPSIS
        Speichert ein Inventar mit Zeitstempel als JSON-Datei.
    .DESCRIPTION
        Standardordner ist %LOCALAPPDATA%\SoftwareInventory\scans. Der Dateiname
        enthält den Zeitpunkt (UTC), z. B. 20261024-153000-123.json.
    .EXAMPLE
        Get-SoftwareInventory | Save-InventorySnapshot
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject,

        [string] $Directory = (Get-DefaultSnapshotDirectory)
    )

    begin {
        $records = [System.Collections.Generic.List[object]]::new()
    }
    process {
        foreach ($item in $InputObject) { $records.Add($item) }
    }
    end {
        $now = [datetime]::UtcNow
        $path = Join-Path $Directory ($now.ToString('yyyyMMdd-HHmmss-fff') + '.json')
        if (-not $PSCmdlet.ShouldProcess($path, (Get-LocalizedString 'ConfirmSaveSnapshot'))) { return }

        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        $snapshot = [ordered]@{
            SchemaVersion = $script:SnapshotSchemaVersion
            CreatedAt     = $now.ToString('o')
            ModuleVersion = [string] $MyInvocation.MyCommand.Module.Version
            Records       = $records
        }
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8NoBOM
        Get-Item -LiteralPath $path
    }
}
