$script:SnapshotSchemaVersion = 1

function Get-DefaultSnapshotDirectory {
    Join-Path $env:LOCALAPPDATA 'SoftwareInventory\scans'
}

function Get-RecordIdentity {
    # Stabiler Schlüssel über Versionen hinweg; der Name enthält oft die Version.
    param($Record)
    if ($Record.RegistryKey) { return "reg:$($Record.RegistryKey)".ToLowerInvariant() }
    if ($Record.PackageFamilyName) { return "pfn:$($Record.PackageFamilyName)".ToLowerInvariant() }
    if ($Record.WingetId) { return "winget:$($Record.WingetId)".ToLowerInvariant() }
    "name:$($Record.Name)".ToLowerInvariant()
}
