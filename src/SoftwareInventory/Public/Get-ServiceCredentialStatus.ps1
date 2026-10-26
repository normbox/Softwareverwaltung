function Get-ServiceCredentialStatus {
    <#
    .SYNOPSIS
        Zeigt, ob für NVD und GitHub ein Schlüssel hinterlegt ist und woher er kommt.
    .DESCRIPTION
        Gibt nie den Schlüssel selbst aus, nur ob er vorhanden ist. Source nennt die Ablage, die
        tatsächlich benutzt wird: CredentialManager vor Environment; ohne Schlüssel $null.
    .PARAMETER Service
        NVD, GitHub oder beide (Standard).
    .EXAMPLE
        Get-ServiceCredentialStatus
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.CredentialStatus')]
    param(
        [ValidateSet('NVD', 'GitHub')]
        [string[]] $Service = @('NVD', 'GitHub')
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
