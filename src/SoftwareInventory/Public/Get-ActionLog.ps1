function Get-ActionLog {
    <#
    .SYNOPSIS
        Zeigt das Protokoll der Aktionen (Aktualisieren, Deinstallieren).
    .DESCRIPTION
        Liest %LOCALAPPDATA%\SoftwareInventory\logs\actions. Pro Aktion erscheint ein Eintrag:
        der Abschluss, oder – wenn er fehlt – der Start mit Result „Incomplete“ (läuft noch oder
        wurde unterbrochen). Beschädigte Zeilen werden mit einer Warnung übersprungen.
        Logs werden beim Laden des Moduls bereinigt (Standard: 30 Tage, 100 MB; Set-InventorySetting).
    .PARAMETER After
        Nur Aktionen, die ab diesem Zeitpunkt gestartet wurden.
    .PARAMETER Before
        Nur Aktionen, die vor diesem Zeitpunkt gestartet wurden.
    .PARAMETER Name
        Programmname; Platzhalter wie * sind erlaubt.
    .PARAMETER Last
        Nur die letzten n Aktionen.
    .EXAMPLE
        Get-ActionLog -After (Get-Date).AddDays(-7) | Format-Table StartedAt, Action, Name, Result
    .EXAMPLE
        Get-ActionLog -Result Failed, NotVerified -Last 10
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.ActionLogEntry')]
    param(
        [datetime] $After,
        [datetime] $Before,
        [string] $Name,
        [ValidateSet('Update', 'Uninstall')]
        [string] $Action,
        [string[]] $Result,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Last
    )

    $byId = [ordered]@{}
    foreach ($entry in Read-ActionLogEntry) {
        $id = [string] $entry.ActionId
        if (-not $byId.Contains($id)) { $byId[$id] = @{ Started = $null; Completed = $null } }
        $byId[$id][$entry.Phase] = $entry
    }

    $items = foreach ($id in $byId.Keys) {
        $pair = $byId[$id]
        $source = if ($pair.Completed) { $pair.Completed } else { $pair.Started }
        if (-not $source) { continue }
        $item = [ordered]@{ PSTypeName = 'SoftwareInventory.ActionLogEntry' }
        foreach ($p in $source.PSObject.Properties) { $item[$p.Name] = $p.Value }
        if (-not $pair.Completed) {
            $item.Result = 'Incomplete'
            $item.Message = 'Kein Abschluss protokolliert: Die Aktion läuft noch oder wurde unterbrochen.'
        }
        $item.StartedAt = ConvertTo-LogTime $(if ($pair.Started) { $pair.Started.Timestamp } elseif ($source.PSObject.Properties['StartedAt']) { $source.StartedAt } else { $source.Timestamp })
        $item.CompletedAt = if ($pair.Completed) { ConvertTo-LogTime $pair.Completed.Timestamp } else { $null }
        [pscustomobject] $item
    }

    $items = @($items | Where-Object {
            ($null -eq $After -or ($_.StartedAt -and $_.StartedAt -ge $After.ToUniversalTime())) -and
            ($null -eq $Before -or ($_.StartedAt -and $_.StartedAt -lt $Before.ToUniversalTime())) -and
            (-not $Name -or $_.Name -like $Name) -and
            (-not $Action -or $_.Action -eq $Action) -and
            (-not $Result -or $_.Result -in $Result)
        } | Sort-Object StartedAt)
    if ($Last) { $items = @($items | Select-Object -Last $Last) }
    foreach ($item in $items) { $item }
}

function ConvertTo-LogTime {
    # ISO-Zeitstempel aus dem Protokoll als UTC-DateTime; Unlesbares wird $null.
    param($Value)
    $parsed = [datetime]::MinValue
    if ($Value -and [datetime]::TryParse([string] $Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref] $parsed)) {
        return $parsed
    }
    $null
}
