function Get-ServiceTermsNotice {
    <#
    .SYNOPSIS
        Zeigt Hinweise zu den Nutzungsbedingungen der externen Dienste, passend zu Privat oder Firma.
    .DESCRIPTION
        Reine Information: Die Funktion schaltet nichts ein oder aus und speichert nichts.
        Die Texte sind Kurzfassungen; maßgeblich sind die verlinkten Bedingungen.
        Ohne -Usage gilt die gespeicherte Angabe; fehlt auch diese, kommen nur die allgemeinen Hinweise.
    .PARAMETER Usage
        Private oder Company.
    .EXAMPLE
        Get-ServiceTermsNotice -Usage Company | Format-List
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.ServiceTermsNotice')]
    param(
        [ValidateSet('Private', 'Company')]
        [string] $Usage
    )

    if (-not $Usage) { $Usage = (Read-InventorySetting).Usage }
    foreach ($entry in $script:ServiceTerms) {
        [pscustomobject] [ordered]@{
            PSTypeName = 'SoftwareInventory.ServiceTermsNotice'
            Service    = $entry.Service
            Name       = $entry.Name
            Terms      = $entry.Terms
            UsageHint  = if ($Usage -eq 'Company') { $entry.Company } else { $null }
            Url        = $entry.Url
            General    = if ($Usage) { $script:ServiceTermsGeneral[$Usage] } else { $null }
        }
    }
}
