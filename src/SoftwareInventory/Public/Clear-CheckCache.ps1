function Clear-CheckCache {
    <#
    .SYNOPSIS
        Verwirft die zwischengespeicherten Online-Ergebnisse eines Programms.
    .DESCRIPTION
        Löscht die Einträge, die Versions- und Sicherheitsprüfung für dieses Programm in dieser Version
        benutzt haben (laut Index), und den Index selbst. Die nächste Prüfung fragt die Dienste neu.
        Der KEV-Katalog gilt für alle Programme und bleibt erhalten. Der CIRCL-Bestand gilt je Produkt
        (unabhängig von der Version) und bleibt ebenfalls erhalten; er wird bei der nächsten Prüfung nur
        um die Änderungen seit dem letzten Abruf ergänzt. Die App ruft das nach jeder Aktion auf.
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
        $circl = (Join-Path (Get-CacheDirectory) 'CIRCL').TrimEnd('\') + '\'
        foreach ($file in @(if ($index) { @($index.Update) + @($index.Vulnerability) }) | Where-Object { $_ } | Sort-Object -Unique) {
            # Nur Dateien im Cache-Ordner, nie den gemeinsamen KEV-Katalog.
            $full = [System.IO.Path]::GetFullPath($file)
            if (-not $full.StartsWith($cache, [StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($kev, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($full.StartsWith($circl, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $full) -like 'store-*.json') {
                if (Test-Path -LiteralPath $full) { New-Item -ItemType File -Path (Get-CirclDueFile $full) -Force | Out-Null }
                continue
            }
            Remove-Item -LiteralPath $full -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}
