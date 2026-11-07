function Set-AdvisorContext {
    <#
    .SYNOPSIS
        Übergibt dem KI-Berater die Bewertungen des letzten Scans.
    .DESCRIPTION
        Die Tools des Beraters arbeiten nur mit diesen Daten. Ohne Aufruf (oder nach -Clear) antworten sie
        mit NoScanData; das Modul liest nie selbst ein, weil ein Scan externe Dienste abfragt.
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

    if (-not $PSCmdlet.ShouldProcess((Get-LocalizedString 'AdvisorContextTarget'), (Get-LocalizedString 'AdvisorContextAction'))) { return }
    # Direkt zuweisen: Aus einem if heraus würde ein leeres Array zu $null, und ein Scan ohne Programme
    # wäre nicht von „kein Scan“ zu unterscheiden.
    if ($Clear) { $script:AdvisorContext = $null }
    else { $script:AdvisorContext = @($Rating | Where-Object { $_ -and $_.PSObject.Properties['Record'] }) }
}
