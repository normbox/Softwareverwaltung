function Clear-CheckCache {
    <#
    .SYNOPSIS
        Verwirft die zwischengespeicherten Online-Ergebnisse eines Programms.
    .DESCRIPTION
        Löscht die Einträge, die Versions- und Sicherheitsprüfung für dieses Programm in dieser Version
        benutzt haben (laut Index), und den Index selbst. Die nächste Prüfung fragt die Dienste neu.
        Der KEV-Katalog gilt für alle Programme und bleibt erhalten. Die App ruft das nach jeder Aktion auf.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object Name -like '7-Zip*' | Clear-CheckCache
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Datensatz aus Get-SoftwareInventory/Get-PortableSoftware oder Ergebnis von Get-SecurityRating
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject
    )

    process {
        $record = Get-ActionRecord $InputObject
        if (-not $record -or -not $record.PSObject.Properties['Name']) {
            Write-Error (Get-LocalizedString 'ErrorNotInventoryRecord')
            return
        }
        $path = Get-CheckIndexFile $record
        if (-not (Test-Path -LiteralPath $path)) { return }
        if (-not $PSCmdlet.ShouldProcess($record.Name, (Get-LocalizedString 'ConfirmClearCheckCache'))) { return }
        $index = $null
        try { $index = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Write-Verbose "Index unlesbar: $path" }
        $cache = (Get-CacheDirectory).TrimEnd('\') + '\'
        $kev = (Join-Path (Get-CacheDirectory) 'KEV').TrimEnd('\') + '\'
        foreach ($file in @(if ($index) { @($index.Update) + @($index.Vulnerability) }) | Where-Object { $_ } | Sort-Object -Unique) {
            # Nur Dateien im Cache-Ordner, nie den gemeinsamen KEV-Katalog.
            $full = [System.IO.Path]::GetFullPath($file)
            if (-not $full.StartsWith($cache, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($kev, [StringComparison]::OrdinalIgnoreCase)) { continue }
            Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
