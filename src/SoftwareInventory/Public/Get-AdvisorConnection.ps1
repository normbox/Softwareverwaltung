function Get-AdvisorConnection {
    <#
    .SYNOPSIS
        Liefert die Verbindungsdaten für den KI-Server an die App.
    .DESCRIPTION
        Für die Anbieter-Schnittstelle der App: Adresse (ohne Angabe die der Vorgabe), Modell, Anbieterart
        und den API-Schlüssel als SecureString. Der Schlüssel ist nur für den Request-Header bestimmt und
        darf nie in Protokolle, Fehlermeldungen oder an das Modell gelangen. Ohne Schlüssel ist ApiKey $null.
        Ob die Adresse lokal ist, prüft Set-InventorySetting beim Speichern und die App beim Verbinden.
    .OUTPUTS
        Enabled, Preset, Endpoint, Model, ProviderKind (vorerst immer Local), ApiKey, HasApiKey.
    .EXAMPLE
        Get-AdvisorConnection | Select-Object Endpoint, Model, HasApiKey
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorConnection')]
    param()

    $advisor = (Read-InventorySetting).Advisor
    $endpoint = $advisor.Endpoint
    if (-not $endpoint -and $advisor.Preset -and $script:AdvisorPresets.Contains($advisor.Preset)) {
        $endpoint = $script:AdvisorPresets[$advisor.Preset].Endpoint
    }
    $secret = Get-ServiceSecret -Service Advisor
    $apiKey = $null
    if ($secret) {
        $apiKey = [System.Security.SecureString]::new()
        foreach ($c in $secret.ToCharArray()) { $apiKey.AppendChar($c) }
        $apiKey.MakeReadOnly()
    }
    [pscustomobject] [ordered]@{
        PSTypeName   = 'SoftwareInventory.AdvisorConnection'
        Enabled      = [bool] $advisor.Enabled
        Preset       = $advisor.Preset
        Endpoint     = $endpoint
        Model        = $advisor.Model
        ProviderKind = 'Local'
        ApiKey       = $apiKey
        HasApiKey    = $null -ne $apiKey
    }
}
