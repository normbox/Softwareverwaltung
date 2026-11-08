function Update-IncompleteActionLog {
    <#
    .SYNOPSIS
        Trägt den Abschluss von Aktionen nach, deren Ende nicht beobachtet wurde (App war geschlossen).
    .DESCRIPTION
        Der Helfer läuft unabhängig von der App weiter. Wird sie während einer Aktion geschlossen, fehlt
        im Protokoll der Abschluss. Diese Funktion vergleicht für jeden offenen Eintrag den Zustand mit dem
        Stand vor der Aktion und schreibt einen Abschluss mit Result „Interrupted“:
          - Ziel erreicht (Version höher bzw. Programm entfernt): sofort.
          - Keine Änderung erkennbar: erst nach WaitMinutes, weil die Aktion noch laufen kann.
    .PARAMETER WaitMinutes
        Ab diesem Alter gilt ein offener Eintrag ohne erkennbare Änderung als beendet (Standard 75:
        60 Minuten Zeitgrenze einer Aktion plus Puffer).
    .OUTPUTS
        Je nachgetragener Aktion ein Objekt mit ActionId, Name, Action, Result, Message und VersionAfter.
    .EXAMPLE
        Update-IncompleteActionLog | Format-Table Name, Action, VersionAfter
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [ValidateRange(0, 10080)]
        [int] $WaitMinutes = 75
    )

    $byId = [ordered]@{}
    foreach ($entry in Read-ActionLogEntry) {
        $id = [string] $entry.ActionId
        if (-not $byId.Contains($id)) { $byId[$id] = @{ Started = $null; Completed = $null } }
        $byId[$id][$entry.Phase] = $entry
    }

    foreach ($id in $byId.Keys) {
        $started = $byId[$id].Started
        if (-not $started -or $byId[$id].Completed -or $started.Action -notin 'Update', 'Uninstall') { continue }

        $record = [pscustomobject] @{
            Name = $started.Name; RegistryKey = (Get-RecordValue $started 'RegistryKey')
            WingetId = (Get-RecordValue $started 'WingetId'); WingetSource = (Get-RecordValue $started 'WingetSource')
        }
        $after = Get-InstalledState -Record $record
        $reached = $false
        $versionBefore = Get-RecordValue $started 'VersionBefore'
        # Ohne Registry-Schlüssel und winget-ID (Identity leer) lässt sich der Zustand nicht lesen.
        if ($after.Identity -and ($started.Action -eq 'Uninstall' -or $versionBefore)) {
            $before = [pscustomobject] @{ Version = $versionBefore; Identity = $after.Identity; WingetVersion = $null }
            $reached = Test-ActionStateReached -Action $started.Action -Before $before -After $after
        }

        if ($reached) {
            $message = if ($started.Action -eq 'Uninstall') { New-InventoryMessage ActionInterruptedRemoved }
            else { New-InventoryMessage ActionInterruptedReached $after.Version }
        }
        else {
            $startedAt = ConvertTo-LogTime $started.Timestamp
            if ($startedAt -and $startedAt -gt [datetime]::UtcNow.AddMinutes(-$WaitMinutes)) { continue }
            $message = New-InventoryMessage ActionInterruptedUnknown
        }
        if (-not $PSCmdlet.ShouldProcess($started.Name, $message.Text)) { continue }

        $data = [ordered]@{}
        foreach ($p in $started.PSObject.Properties) { $data[$p.Name] = $p.Value }
        $data.Result = 'Interrupted'
        $data.Message = $message
        $data.VersionAfter = $after.Version
        $data.PresentAfter = $after.Present
        $data.CompletedAt = [datetime]::UtcNow.ToString('o')
        Write-ActionLogEntry -Phase Completed -Data $data

        [pscustomobject] @{
            ActionId = $id; Name = $started.Name; Action = $started.Action
            Result = 'Interrupted'; Message = $message; VersionAfter = $after.Version
        }
    }
}
