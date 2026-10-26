function Get-AdvisorEndpointPreset {
    <#
    .SYNOPSIS
        Listet die Vorgaben für lokale KI-Server mit OpenAI-kompatibler Schnittstelle.
    .DESCRIPTION
        Ollama, LM Studio und Unsloth Studio mit ihren Standardadressen sowie „Eigene Adresse“ (Custom).
        Die Adresse bleibt in den Einstellungen änderbar, falls ein anderer Port eingestellt ist.
        RequiresApiKey nennt Server, die einen Schlüssel verlangen (Set-ServiceCredential -Service Advisor).
        Name ist der feste Code; Label und Note kommen in der Sprache der Oberfläche.
    .EXAMPLE
        Get-AdvisorEndpointPreset | Format-Table Name, Label, Endpoint
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorEndpointPreset')]
    param()

    foreach ($name in $script:AdvisorPresets.Keys) {
        $p = $script:AdvisorPresets[$name]
        $noteKey = "AdvisorPresetNote$name"
        $note = Get-LocalizedString $noteKey
        [pscustomobject] [ordered]@{
            PSTypeName     = 'SoftwareInventory.AdvisorEndpointPreset'
            Name           = $name
            Label          = if ($p.Label) { $p.Label } else { Get-LocalizedString "AdvisorPresetLabel$name" }
            Endpoint       = $p.Endpoint
            RequiresApiKey = $p.RequiresApiKey
            Note           = if ($note -ne $noteKey) { $note } else { $null }
        }
    }
}
