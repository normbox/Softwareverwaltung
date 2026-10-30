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
        if ($script:CheckProgress -and $script:CheckProgress.Id -eq $Id) { $script:CheckProgress = $null }
        return
    }
    # Ohne Namen ein Leerzeichen: sonst setzt PowerShell „Processing“ in seiner eigenen Sprache ein.
    $progress = @{ Id = $Id; Activity = $text; Status = $(if ($Name) { $Name } else { ' ' }) }
    if ($Total -gt 1) {
        $progress.Activity = Get-LocalizedString "${Activity}Counted" $Index, $Total
        $progress.PercentComplete = [math]::Min(100, [int] (($Index - 1) * 100 / $Total))
    }
    # Für Write-CheckStep: die zweite Zeile gehört zu dieser Anzeige.
    $script:CheckProgress = $progress
    $script:CheckStep = $null
    Write-Progress @progress
}

# Zuletzt gemeldete Anzeige (Write-CheckProgress) und der aktuelle Schritt darunter (Write-CheckStep).
$script:CheckProgress = $null
$script:CheckStep = $null

function Write-CheckStep {
    <#
    .SYNOPSIS
        Zweite Zeile der laufenden Anzeige: der aktuelle Schritt, z. B. „CIRCL: Seite 37 von 149“.
    .DESCRIPTION
        -Key ist der Schlüssel in SoftwareInventory.Strings.psd1. Mit -Wait wird nur eine Wartezeit an
        den aktuellen Schritt gehängt („… · Warte 3 s (Anfragelimit CIRCL)“), damit die Anzeige nicht
        für jede kurze Pause wechselt. Ohne laufende Anzeige (Aufruf außerhalb einer Prüfung) passiert nichts.
    #>
    param(
        [Parameter(Mandatory)] [string] $Key,
        [object[]] $Arguments = @(),
        [switch] $Wait
    )
    if (-not $script:CheckProgress) { return }
    $text = Get-LocalizedString $Key $Arguments
    $operation = if ($Wait -and $script:CheckStep) { Get-LocalizedString 'StepWithWait' $script:CheckStep, $text } else { $text }
    if (-not $Wait) { $script:CheckStep = $text }
    $progress = $script:CheckProgress.Clone()
    $progress.CurrentOperation = $operation
    Write-Progress @progress
}

function Format-RemainingTime {
    # Grobe Restzeit als Text: „noch etwa 6 Min.“, unter einer Minute „noch unter 1 Min.“.
    param([double] $Seconds)
    if ($Seconds -lt 60) { return Get-LocalizedString 'StepRemainingUnderMinute' }
    Get-LocalizedString 'StepRemainingMinutes' ([int] [math]::Ceiling($Seconds / 60))
}
