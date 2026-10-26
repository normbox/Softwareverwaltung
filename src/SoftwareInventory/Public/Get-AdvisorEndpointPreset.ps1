function Get-AdvisorEndpointPreset {
    <#
    .SYNOPSIS
        Listet die Vorgaben für lokale KI-Server mit OpenAI-kompatibler Schnittstelle.
    .DESCRIPTION
        Ollama, LM Studio und Unsloth Studio mit ihren Standardadressen sowie „Eigene Adresse“.
        Die Adresse bleibt in den Einstellungen änderbar, falls ein anderer Port eingestellt ist.
        RequiresApiKey nennt Server, die einen Schlüssel verlangen (Set-ServiceCredential -Service Advisor).
    .EXAMPLE
        Get-AdvisorEndpointPreset | Format-Table Name, Label, Endpoint
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorEndpointPreset')]
    param()

    foreach ($name in $script:AdvisorPresets.Keys) {
        $p = $script:AdvisorPresets[$name]
        [pscustomobject] [ordered]@{
            PSTypeName     = 'SoftwareInventory.AdvisorEndpointPreset'
            Name           = $name
            Label          = $p.Label
            Endpoint       = $p.Endpoint
            RequiresApiKey = $p.RequiresApiKey
            Note           = $p.Note
        }
    }
}
