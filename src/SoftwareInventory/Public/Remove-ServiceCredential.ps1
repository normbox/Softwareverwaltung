function Remove-ServiceCredential {
    <#
    .SYNOPSIS
        Löscht einen gespeicherten API-Schlüssel aus der Windows-Anmeldeinformationsverwaltung.
    .DESCRIPTION
        Eine gesetzte Umgebungsvariable bleibt unberührt und wird danach wieder benutzt.
    .PARAMETER Service
        NVD oder GitHub.
    .EXAMPLE
        Remove-ServiceCredential -Service GitHub
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SoftwareInventory.CredentialStatus')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('NVD', 'GitHub')]
        [string] $Service
    )

    if ($PSCmdlet.ShouldProcess((Get-CredentialTarget $Service), 'Schlüssel löschen')) {
        Initialize-CredentialInterop
        [void] [SoftwareInventory.CredentialStore]::Delete((Get-CredentialTarget $Service))
    }
    Get-ServiceCredentialStatus -Service $Service
}
