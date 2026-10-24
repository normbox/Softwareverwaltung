function Get-ScanDrive {
    <#
    .SYNOPSIS
        Listet die Laufwerke, die Get-PortableSoftware durchsuchen kann.
    .DESCRIPTION
        Feste und Wechsellaufwerke, die bereit sind. Netzlaufwerke werden nicht angeboten,
        weil ein Scan dort sehr lange dauern kann; sie lassen sich über -Path trotzdem angeben.
    .EXAMPLE
        Get-ScanDrive | Format-Table
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.ScanDrive')]
    param()

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -notin 'Fixed', 'Removable' -or -not $drive.IsReady) { continue }
        [pscustomobject] @{
            PSTypeName = 'SoftwareInventory.ScanDrive'
            Drive      = $drive.Name.TrimEnd('\')
            Label      = $drive.VolumeLabel
            Type       = [string] $drive.DriveType
            SizeGB     = [math]::Round($drive.TotalSize / 1GB)
            FreeGB     = [math]::Round($drive.AvailableFreeSpace / 1GB)
            IsDefault  = $drive.DriveType -eq 'Fixed'
        }
    }
}
