function Get-AdvisorDataPreview {
    <#
    .SYNOPSIS
        Zeigt, was der KI-Berater auf einer Freigabestufe an das Modell schicken würde.
    .DESCRIPTION
        Für die Vorschau in den Einstellungen: genau die bereinigten Antworten der Tools (JSON), wie sie
        das Modell bekäme – get_inventory mit den ersten 5 Programmen und get_program_details für das
        erste Programm (auf Stufe 0 nur die Übersicht). Es wird nichts gesendet.
        Ohne -Level gilt die eingestellte Stufe der Anbieterart. Ohne Daten aus einem Scan ist HasScanData
        $false und Inventory enthält nur den Fehler NoScanData.
    .PARAMETER Level
        Freigabestufe 0 bis 4, z. B. die gerade in den Einstellungen gewählte.
    .PARAMETER ProviderKind
        Local oder External; ohne -Level bestimmt sie die Stufe aus den Einstellungen.
    .OUTPUTS
        Level, HasScanData, Inventory (JSON), Details (JSON oder $null), ProgramId (oder $null).
    .EXAMPLE
        (Get-AdvisorDataPreview -Level 1).Inventory
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.AdvisorDataPreview')]
    param(
        [ValidateRange(0, 4)]
        [Nullable[int]] $Level,

        [ValidateSet('Local', 'External')]
        [string] $ProviderKind = 'Local'
    )

    $effective = if ($null -ne $Level) { [int] $Level } else { Get-AdvisorShareLevel -ProviderKind $ProviderKind }
    $inventoryArgs = if ($effective -eq 0) { '{}' } else { '{"limit":5}' }
    $inventory = Invoke-AdvisorToolAtLevel -Name get_inventory -ArgumentsJson $inventoryArgs -Level $effective
    $details = $null
    $programId = $null
    $hasScanData = Test-AdvisorContext
    if ($hasScanData -and $effective -ge 1) {
        $first = $inventory.Content | ConvertFrom-Json -AsHashtable
        $programId = @($first['programs']) | Select-Object -First 1 | ForEach-Object { $_['id'] }
        if ($programId) {
            $details = (Invoke-AdvisorToolAtLevel -Name get_program_details -ArgumentsJson (@{ id = $programId } | ConvertTo-Json -Compress) -Level $effective).Content
        }
    }
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.AdvisorDataPreview'
        Level      = $effective
        HasScanData = $hasScanData
        Inventory  = $inventory.Content
        Details    = $details
        ProgramId  = $programId
    }
}
