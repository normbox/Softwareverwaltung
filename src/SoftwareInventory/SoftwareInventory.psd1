@{
    RootModule           = 'SoftwareInventory.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '5d0c1f7e-6b2a-4e8f-9a51-3c7d2e4b8f10'
    Author               = 'normbox'
    Copyright            = '(c) normbox. GPLv3.'
    Description          = 'Inventarisiert installierte und portable Software unter Windows (Registry, winget, Store-Apps, Ausführungsspuren, Dateiscan).'
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Get-SoftwareInventory'
        'Resolve-InstallLocation'
        'Clear-CheckCache'
        'Get-RefreshEstimate'
        'Get-UpdateQueuePlan'
        'Invoke-UpdateQueue'
        'Get-StoreAgreementNotice'
        'Save-InventorySnapshot'
        'Get-InventorySnapshot'
        'Compare-InventorySnapshot'
        'Get-PortableSoftware'
        'Invoke-InventoryScan'
        'Get-ScanDrive'
        'Get-InventorySetting'
        'Set-InventorySetting'
        'Get-SettingPreset'
        'Get-ServiceTermsNotice'
        'Get-AdvisorEndpointPreset'
        'Get-AdvisorTool'
        'Invoke-AdvisorTool'
        'Set-AdvisorContext'
        'Compare-SoftwareVersion'
        'Test-SoftwareUpdate'
        'Get-SoftwareVulnerability'
        'Find-CpeCandidate'
        'Get-CpeMappingReport'
        'Set-CpeMapping'
        'Get-CpeMapping'
        'Remove-CpeMapping'
        'Get-SecurityRating'
        'Export-SecurityReport'
        'Get-ActionLog'
        'Update-Software'
        'Uninstall-Software'
        'Install-WingetPackageManager'
        'Find-InstalledSoftware'
        'Test-WingetAvailability'
        'Set-ServiceCredential'
        'Remove-ServiceCredential'
        'Get-ServiceCredentialStatus'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            LicenseUri = 'https://www.gnu.org/licenses/gpl-3.0.html'
            ProjectUri = 'https://github.com/normbox/Softwareverwaltung'
        }
    }
}
