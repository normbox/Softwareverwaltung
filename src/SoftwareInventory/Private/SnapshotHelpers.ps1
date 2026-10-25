$script:SnapshotSchemaVersion = 3   # 2: Felder für portable Programme, 3: Companions

function Get-DefaultSnapshotDirectory {
    Join-Path $env:LOCALAPPDATA 'SoftwareInventory\scans'
}

function Get-RecordIdentity {
    # Stabiler Schlüssel über Versionen hinweg; der Name enthält oft die Version.
    param($Record)
    if ($Record.RegistryKey) { return "reg:$($Record.RegistryKey)".ToLowerInvariant() }
    if ($Record.PackageFamilyName) { return "pfn:$($Record.PackageFamilyName)".ToLowerInvariant() }
    if ($Record.WingetId) { return "winget:$($Record.WingetId)".ToLowerInvariant() }
    if ($Record.FilePath) { return "file:$($Record.FilePath)".ToLowerInvariant() }
    "name:$($Record.Name)".ToLowerInvariant()
}
