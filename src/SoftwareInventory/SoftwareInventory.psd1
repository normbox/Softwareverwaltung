@{
    RootModule           = 'SoftwareInventory.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '5d0c1f7e-6b2a-4e8f-9a51-3c7d2e4b8f10'
    Author               = 'normbox'
    Copyright            = '(c) normbox. GPL-3.0-only.'
    Description          = 'Inventarisiert installierte und portable Software unter Windows (Registry, winget, Store-Apps, Ausführungsspuren, Dateiscan).'
    PowerShellVersion    = '7.6'
    CompatiblePSEditions = @('Core')
    # Fertig übersetzter Windows-Zugriff statt Add-Type (auch im Constrained Language Mode ladbar).
    RequiredAssemblies   = @('lib\SoftwareInventory.Native.dll')
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
        'Get-InventorySettingHint'
        'Get-SettingPreset'
        'Get-ServiceTermsNotice'
        'Get-AdvisorEndpointPreset'
        'Get-AdvisorEndpointCheck'
        'Get-AdvisorDataPreview'
        'Get-AdvisorConnection'
        'Protect-AdvisorText'
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
        'Update-IncompleteActionLog'
        'Update-Software'
        'Uninstall-Software'
        'Install-WingetPackageManager'
        'Get-HelperCopyStatus'
        'Remove-HelperCopy'
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
