@{
    RootModule           = 'SoftwareInventory.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '5d0c1f7e-6b2a-4e8f-9a51-3c7d2e4b8f10'
    Author               = 'normbox'
    Copyright            = '(c) normbox. GPLv3.'
    Description          = 'Inventarisiert installierte Software unter Windows (Registry, winget, Store-Apps).'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Get-SoftwareInventory'
        'Save-InventorySnapshot'
        'Get-InventorySnapshot'
        'Compare-InventorySnapshot'
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
