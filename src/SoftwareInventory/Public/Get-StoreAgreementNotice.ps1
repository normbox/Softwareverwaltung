function Get-StoreAgreementNotice {
    <#
    .SYNOPSIS
        Vereinbarung der winget-Quelle „msstore“ zum Anzeigen vor der ersten Aktion mit einem Store-Paket.
    .DESCRIPTION
        Liefert den Text (Sprache der Oberfläche), den Link zu den „Terms of Transaction“ des Microsoft Store
        und, falls schon zugestimmt, den Zeitpunkt. Zustimmen mit Set-InventorySetting -StoreAgreementAccepted $true.
    .EXAMPLE
        Get-StoreAgreementNotice | Format-List
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.StoreAgreementNotice')]
    param()
    $setting = Read-InventorySetting
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.StoreAgreementNotice'
        Text       = Get-LocalizedString 'StoreAgreementText'
        Url        = $script:StoreTermsUrl
        Accepted   = Test-StoreAgreementAccepted -Setting $setting
        AcceptedAt = $setting.Agreements.MsStore
    }
}
