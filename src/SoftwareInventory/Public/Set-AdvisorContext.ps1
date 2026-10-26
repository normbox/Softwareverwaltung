function Set-AdvisorContext {
    <#
    .SYNOPSIS
        Übergibt dem KI-Berater die Bewertungen des letzten Scans.
    .DESCRIPTION
        Die Tools des Beraters arbeiten mit diesen Daten, damit nicht jede Frage einen neuen Scan
        auslöst. Ohne Aufruf liest der Berater beim ersten Tool-Aufruf selbst einmal ein.
        -Clear verwirft die Daten (z. B. nach geänderten Einstellungen).
    .EXAMPLE
        $ratings = Get-SoftwareInventory | Get-SecurityRating
        Set-AdvisorContext -Rating $ratings
    #>
    [CmdletBinding(DefaultParameterSetName = 'Set', SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Set')]
        [AllowEmptyCollection()]
        [object[]] $Rating,

        [Parameter(Mandatory, ParameterSetName = 'Clear')]
        [switch] $Clear
    )

    if (-not $PSCmdlet.ShouldProcess('KI-Berater', 'Daten des letzten Scans übernehmen')) { return }
    $script:AdvisorContext = if ($Clear) { $null } else { @($Rating | Where-Object { $_ -and $_.PSObject.Properties['Record'] }) }
}
