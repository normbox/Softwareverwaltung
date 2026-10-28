function Test-WingetAvailability {
    <#
    .SYNOPSIS
        Prüft, ob winget und das PowerShell-Modul Microsoft.WinGet.Client nutzbar sind.
    .DESCRIPTION
        Das Inventar braucht das Modul (Get-WinGetPackage), Aktualisieren und Deinstallieren
        braucht winget.exe aus App Installer. Fehlt eines davon, läuft alles andere weiter;
        Message beschreibt dann in einfachen Worten, was fehlt und was das bedeutet.
        InstallUrl führt zu App Installer im Microsoft Store. Es wird nichts installiert.
    .EXAMPLE
        Test-WingetAvailability | Format-List
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.WingetStatus')]
    param()

    $cli = Get-WingetExecutable
    $command = Get-Command Get-WinGetPackage -ErrorAction SilentlyContinue
    $moduleVersion = if ($command -and $command.Module) { [string] $command.Module.Version } else { $null }

    $message = if ($cli -and $command) { $null }
    elseif (-not $cli -and -not $command) {
        New-InventoryMessage WingetStatusMissing
    }
    elseif (-not $cli) {
        New-InventoryMessage WingetStatusCliMissing
    }
    else {
        New-InventoryMessage WingetStatusModuleMissing
    }

    [pscustomobject] [ordered]@{
        PSTypeName      = 'SoftwareInventory.WingetStatus'
        Available       = [bool] ($cli -and $command)
        CliAvailable    = [bool] $cli
        CliPath         = $cli
        ModuleAvailable = [bool] $command
        ModuleVersion   = $moduleVersion
        Message         = $message
        InstallUrl      = if ($cli) { $null } else { 'https://apps.microsoft.com/detail/9NBLGGH4NNS1' }
    }
}
