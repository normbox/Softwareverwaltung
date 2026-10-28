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
            Name       = Get-LocalizedString "ServiceTerms$($entry.Service)Name"
            Terms      = Get-LocalizedString "ServiceTerms$($entry.Service)Terms"
            UsageHint  = if ($Usage -eq 'Company' -and $entry.CompanyHint) { Get-LocalizedString "ServiceTerms$($entry.Service)Company" } else { $null }
            Url        = $entry.Url
            General    = if ($Usage) { Get-LocalizedString "ServiceTermsGeneral$Usage" } else { $null }
        }
    }
}
