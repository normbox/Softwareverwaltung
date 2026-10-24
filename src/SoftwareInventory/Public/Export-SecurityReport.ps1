function Export-SecurityReport {
    <#
    .SYNOPSIS
        Schreibt einen HTML-Sicherheitsbericht mit Ampel, Updates und Schwachstellen.
    .DESCRIPTION
        Nimmt Ergebnisse von Get-SecurityRating oder Datensätze (dann wird die Ampel hier
        berechnet). Der Bericht ist eine einzelne Datei ohne externe Ressourcen, sortiert nach
        Dringlichkeit, mit Filtern für „Updates verfügbar“ und „Sicherheitsrisiko“.
        Das Benutzerprofil erscheint als %USERPROFILE%, der Rechnername als %COMPUTERNAME%;
        API-Schlüssel kommen nicht vor.
    .EXAMPLE
        Get-SoftwareInventory | Export-SecurityReport -Path .\bericht.html
    .EXAMPLE
        $ratings = @(Get-SoftwareInventory) + @(Get-PortableSoftware) | Get-SecurityRating
        $ratings | Export-SecurityReport -Path "$env:USERPROFILE\Desktop\Sicherheitsbericht.html"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyCollection()]
        [object[]] $InputObject,

        [Parameter(Mandatory)]
        [string] $Path
    )

    begin { $items = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($item in $InputObject) { if ($null -ne $item) { $items.Add($item) } } }
    end {
        $ratings = @($items | Where-Object { $_.PSObject.TypeNames -contains 'SoftwareInventory.SecurityRating' })
        $records = @($items | Where-Object { $_.PSObject.TypeNames -notcontains 'SoftwareInventory.SecurityRating' })
        if ($records) { $ratings += @($records | Get-SecurityRating) }
        $order = @{ Red = 0; Yellow = 1; Gray = 2; Green = 3 }
        $ratings = @($ratings | Sort-Object @{ Expression = { $order[$_.Rating] } }, Name)

        $html = ConvertTo-SecurityReportHtml -Rating $ratings -Setting (Read-InventorySetting)
        $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not $PSCmdlet.ShouldProcess($full, 'Sicherheitsbericht schreiben')) { return }
        $dir = Split-Path -Parent $full
        if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $full -Value $html -Encoding utf8NoBOM
        Get-Item -LiteralPath $full
    }
}
