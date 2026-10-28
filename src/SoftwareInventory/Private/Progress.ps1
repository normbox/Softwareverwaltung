# Fortschritt der Prüfungen in der Sprache der Oberfläche. Webabfragen und winget-Cmdlets melden
# selbst keinen Fortschritt: ihre englischen Meldungen unterdrücken die Aufrufer mit $ProgressPreference.

function Write-CheckProgress {
    <#
    .SYNOPSIS
        Meldet „<Tätigkeit> (12 von 85)“ mit dem Programmnamen als Status.
    .DESCRIPTION
        -Activity ist der Schlüssel in SoftwareInventory.Strings.psd1. Mit -Total größer als 1 wird der
        Text mit Zähler verwendet (Schlüssel + 'Counted'), sonst der Text ohne Zähler.
        Mit -Completed wird die Anzeige beendet.
    #>
    param(
        [Parameter(Mandatory)] [int] $Id,
        [Parameter(Mandatory)] [string] $Activity,
        [int] $Index,
        [int] $Total,
        [string] $Name,
        [switch] $Completed
    )
    $text = Get-LocalizedString $Activity
    if ($Completed) {
        Write-Progress -Id $Id -Activity $text -Completed
        return
    }
    # Ohne Namen ein Leerzeichen: sonst setzt PowerShell „Processing“ in seiner eigenen Sprache ein.
    $progress = @{ Id = $Id; Activity = $text; Status = $(if ($Name) { $Name } else { ' ' }) }
    if ($Total -gt 1) {
        $progress.Activity = Get-LocalizedString "${Activity}Counted" $Index, $Total
        $progress.PercentComplete = [math]::Min(100, [int] (($Index - 1) * 100 / $Total))
    }
    Write-Progress @progress
}
