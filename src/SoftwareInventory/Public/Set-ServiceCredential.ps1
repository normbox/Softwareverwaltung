function Set-ServiceCredential {
    <#
    .SYNOPSIS
        Speichert einen API-Schlüssel (NVD, lokaler KI-Server) oder ein Token (GitHub) in der Windows-Anmeldeinformationsverwaltung.
    .DESCRIPTION
        Der Eintrag gilt nur für den angemeldeten Benutzer auf diesem PC. Ein gespeicherter Schlüssel
        hat Vorrang vor der Umgebungsvariablen. Der Schlüssel wird nie ausgegeben oder protokolliert.
    .PARAMETER Service
        NVD, GitHub oder Advisor (Schlüssel des lokalen KI-Servers, z. B. Unsloth Studio).
    .PARAMETER Secret
        Der Schlüssel als SecureString, z. B. aus Read-Host -AsSecureString.
    .EXAMPLE
        Set-ServiceCredential -Service NVD -Secret (Read-Host 'NVD-API-Schlüssel' -AsSecureString)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('SoftwareInventory.CredentialStatus')]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('NVD', 'GitHub', 'Advisor')]
        [string] $Service,

        [Parameter(Mandatory)]
        [securestring] $Secret
    )

    if ($Secret.Length -eq 0) { throw (Get-LocalizedString 'ErrorEmptySecret') }
    if ($PSCmdlet.ShouldProcess((Get-CredentialTarget $Service), (Get-LocalizedString 'ConfirmSaveSecret'))) {
        Initialize-CredentialInterop
        [SoftwareInventory.CredentialStore]::Write((Get-CredentialTarget $Service), $Service, $Secret)
    }
    Get-ServiceCredentialStatus -Service $Service
}
