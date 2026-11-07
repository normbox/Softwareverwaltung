function Get-AdvisorTool {
    <#
    .SYNOPSIS
        Beschreibt die Tools des KI-Beraters (Name, Beschreibung, JSON-Schema der Parameter).
    .DESCRIPTION
        Unabhängig vom Anbieter: Die App oder ein Plugin wandelt die Beschreibung in das Format
        seines Servers um (z. B. OpenAI „tools“ mit type function). Kind ist Read (liest Daten)
        oder Proposal (erzeugt nur einen Vorschlag, den der Benutzer bestätigen muss).
        Beschreibungen kommen in der Sprache der Oberfläche. Mit -SystemPrompt kommt stattdessen
        die Systemanweisung für das Modell.
        Mit -ProviderKind gilt deren Freigabestufe: Auf Stufe 0 gibt es nur get_inventory als Übersicht
        ohne Parameter; die anderen Tools fehlen dann.
    .EXAMPLE
        Get-AdvisorTool | Format-Table Name, Kind
    .EXAMPLE
        Get-AdvisorTool -SystemPrompt
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorTool', [string])]
    param(
        [switch] $SystemPrompt,

        [ValidateSet('Local', 'External')]
        [string] $ProviderKind = 'Local'
    )

    if ($SystemPrompt) { return Get-LocalizedString 'AdvisorSystemPrompt' }
    if ((Get-AdvisorShareLevel -ProviderKind $ProviderKind) -eq 0) {
        return [pscustomobject] [ordered]@{
            PSTypeName     = 'SoftwareInventory.AdvisorTool'
            Name           = 'get_inventory'
            Kind           = 'Read'
            Description    = Get-LocalizedString 'AdvisorToolGetInventoryOverview'
            ParametersJson = [ordered]@{ type = 'object'; properties = [ordered]@{}; required = @() } | ConvertTo-Json -Depth 4 -Compress
        }
    }
    foreach ($name in $script:AdvisorTools.Keys) {
        $tool = $script:AdvisorTools[$name]
        [pscustomobject] [ordered]@{
            PSTypeName     = 'SoftwareInventory.AdvisorTool'
            Name           = $name
            Kind           = $tool.Kind
            Description    = Get-LocalizedString $tool.Text
            ParametersJson = ConvertTo-AdvisorSchema $tool | ConvertTo-Json -Depth 8 -Compress
        }
    }
}
