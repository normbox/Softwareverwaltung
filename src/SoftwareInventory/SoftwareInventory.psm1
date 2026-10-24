#Requires -Version 7.4
Set-StrictMode -Version Latest

# Private zuerst laden, damit öffentliche Funktionen darauf zugreifen können.
foreach ($folder in 'Private', 'Public') {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' | ForEach-Object { . $_.FullName }
    }
}
