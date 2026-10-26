function Get-CpeMapping {
    <#
    .SYNOPSIS
        Zeigt die vom Benutzer bestätigten CPE-Zuordnungen.
    #>
    [CmdletBinding()]
    param()
    (Read-CpeMapping).Values | Sort-Object Key
}
