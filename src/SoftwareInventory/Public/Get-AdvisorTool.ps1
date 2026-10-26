function Get-AdvisorTool {
    <#
    .SYNOPSIS
        Beschreibt die Tools des KI-Beraters (Name, Beschreibung, JSON-Schema der Parameter).
    .DESCRIPTION
        Unabhängig vom Anbieter: Die App oder ein Plugin wandelt die Beschreibung in das Format
        seines Servers um (z. B. OpenAI „tools“ mit type function). Kind ist Read (liest Daten)
        oder Proposal (erzeugt nur einen Vorschlag, den der Benutzer bestätigen muss).
        Mit -SystemPrompt kommt stattdessen die Systemanweisung für das Modell.
    .EXAMPLE
        Get-AdvisorTool | Format-Table Name, Kind
    .EXAMPLE
        Get-AdvisorTool -SystemPrompt
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorTool', [string])]
    param([switch] $SystemPrompt)

    if ($SystemPrompt) { return $script:AdvisorSystemPrompt }
    foreach ($name in $script:AdvisorTools.Keys) {
        $tool = $script:AdvisorTools[$name]
        [pscustomobject] [ordered]@{
            PSTypeName     = 'SoftwareInventory.AdvisorTool'
            Name           = $name
            Kind           = $tool.Kind
            Description    = $tool.Description
            ParametersJson = $tool.Parameters | ConvertTo-Json -Depth 8 -Compress
        }
    }
}
