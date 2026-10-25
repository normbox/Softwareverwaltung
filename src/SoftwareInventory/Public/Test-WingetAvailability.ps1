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
        'winget ist nicht verfügbar. Das Inventar kommt nur aus Registry und Store-Apps; Aktualisieren über winget ist nicht möglich.'
    }
    elseif (-not $cli) {
        'winget.exe (App Installer) fehlt. Aktualisieren und Deinstallieren über winget ist nicht möglich; andere Methoden bleiben nutzbar.'
    }
    else {
        'Das PowerShell-Modul Microsoft.WinGet.Client fehlt. Das Inventar enthält keine winget-Daten und keine verfügbaren Updates.'
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
