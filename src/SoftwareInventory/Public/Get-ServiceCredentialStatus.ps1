function Get-ServiceCredentialStatus {
    <#
    .SYNOPSIS
        Zeigt, ob für NVD, CIRCL, GitHub und den KI-Berater ein Schlüssel hinterlegt ist und woher er kommt.
    .DESCRIPTION
        Gibt nie den Schlüssel selbst aus, nur ob er vorhanden ist. Source nennt die Ablage, die
        tatsächlich benutzt wird: CredentialManager vor Environment; ohne Schlüssel $null.
    .PARAMETER Service
        NVD, CIRCL, GitHub, Advisor oder alle (Standard).
    .EXAMPLE
        Get-ServiceCredentialStatus
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.CredentialStatus')]
    param(
        [ValidateSet('NVD', 'CIRCL', 'GitHub', 'Advisor')]
        [string[]] $Service = @('NVD', 'CIRCL', 'GitHub', 'Advisor')
    )

    foreach ($name in $Service) {
        $stored = [bool] (Read-StoredSecret -Service $name)
        $environment = [bool] (Read-EnvironmentSecret -Service $name)
        [pscustomobject] [ordered]@{
            PSTypeName          = 'SoftwareInventory.CredentialStatus'
            Service             = $name
            Stored              = $stored
            EnvironmentVariable = $script:SecretVariable[$name]
            EnvironmentSet      = $environment
            Source              = if ($stored) { 'CredentialManager' } elseif ($environment) { 'Environment' } else { $null }
        }
    }
}
