function Get-HelperCopyStatus {
    <#
    .SYNOPSIS
        Zeigt, ob unter Program Files eine geschützte Kopie des Helfers liegt.
    .EXAMPLE
        Get-HelperCopyStatus
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.HelperCopyStatus')]
    param()
    $root = Get-HelperCopyRoot
    [pscustomobject] @{
        PSTypeName = 'SoftwareInventory.HelperCopyStatus'
        Present    = [bool] (Test-Path -LiteralPath $root)
        Path       = $root
    }
}
