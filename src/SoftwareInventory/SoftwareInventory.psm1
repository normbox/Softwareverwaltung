#Requires -Version 7.6
Set-StrictMode -Version Latest

# Texte zuerst (siehe CLAUDE.md „Mehrsprachig vorbereitet“): Sprache der Oberfläche, sonst Basisdatei.
Import-LocalizedData -BindingVariable Strings -FileName 'SoftwareInventory.Strings.psd1' -BaseDirectory $PSScriptRoot
$script:Strings = $Strings

# Private zuerst laden, damit öffentliche Funktionen darauf zugreifen können.
foreach ($folder in 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }
}

# Logs und Zwischenspeicher räumen sich beim Start selbst auf (siehe CLAUDE.md). Fehler hier
# dürfen das Laden des Moduls nie verhindern.
try {
    $maintenance = (Read-InventorySetting 3>$null).Maintenance
    [void] (Invoke-AppDataCleanup -RetentionDays $maintenance.LogRetentionDays -MaxSizeMB $maintenance.LogMaxSizeMB)
}
catch {
    Write-Verbose "Bereinigung übersprungen: $_"
}
