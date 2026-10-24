function Merge-SoftwareRecord {
    <#
    .SYNOPSIS
        Führt Registry-, Appx- und winget-Datensätze zu einem Datensatz pro Programm zusammen.
    .DESCRIPTION
        Registry und Appx bilden die Grundlage. winget-Datensätze werden über ihre
        Abgleichschlüssel (Registry-Schlüsselname, PackageFullName, PackageFamilyName)
        zugeordnet, ersatzweise über Name und Version. winget-Einträge mit Schlüsseln,
        aber ohne Gegenstück entfallen, da die Grundquellen sie bewusst ausgefiltert haben.
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.SoftwareRecord')]
    param(
        [object[]] $BaseRecord = @(),
        [object[]] $WingetRecord = @()
    )

    $index = @{}
    foreach ($record in $BaseRecord) {
        foreach ($key in $record.MatchKeys) {
            if (-not $index.ContainsKey($key)) { $index[$key] = [System.Collections.Generic.List[object]]::new() }
            $index[$key].Add($record)
        }
    }

    $claimed = [System.Collections.Generic.HashSet[object]]::new()
    $standalone = [System.Collections.Generic.List[object]]::new()

    foreach ($wg in $WingetRecord) {
        $candidates = @($wg.MatchKeys | ForEach-Object { if ($index.ContainsKey($_)) { $index[$_] } } |
                Where-Object { -not $claimed.Contains($_) } | Select-Object -Unique)

        # Ohne Schlüssel (Zuordnungsdaten fehlten) ersatzweise über Name und Version.
        if (-not $candidates -and -not $wg.MatchKeys) {
            $candidates = @($BaseRecord | Where-Object {
                    -not $claimed.Contains($_) -and -not $_.WingetId -and
                    $_.Version -eq $wg.Version -and $_.Name.StartsWith($wg.Name, [StringComparison]::OrdinalIgnoreCase)
                })
        }

        if ($candidates) {
            $target = $candidates | Where-Object Version -eq $wg.Version | Select-Object -First 1
            if (-not $target) { $target = $candidates[0] }
            [void] $claimed.Add($target)
            Merge-WingetIntoRecord -Target $target -Winget $wg
        }
        elseif ($wg.WingetId -and -not $wg.MatchKeys) {
            $wg.InstallType = 'Winget'
            $standalone.Add($wg)
        }
        else {
            # Hat Schlüssel, aber kein Gegenstück: Die Grundquelle hat den Eintrag bewusst
            # ausgefiltert (Framework, Systemkomponente, Update).
            Write-Verbose "winget-Eintrag ohne Gegenstück verworfen: $($wg.Name)"
        }
    }

    @($BaseRecord) + $standalone |
        Where-Object { $null -ne $_ } |
        ForEach-Object { $_.PSObject.Properties.Remove('MatchKeys'); $_ } |
        Sort-Object Name
}

function Merge-WingetIntoRecord {
    param($Target, $Winget)

    $Target.Sources = [string[]] @($Target.Sources + 'Winget' | Select-Object -Unique)
    if ($Winget.WingetId) {
        $Target.WingetId = $Winget.WingetId
        $Target.WingetSource = $Winget.WingetSource
        $Target.AvailableVersion = $Winget.AvailableVersion
    }
    # Appx kennt nur technische Paketnamen; winget liefert den Anzeigenamen.
    if ($Target.InstallType -eq 'MSIX' -and $Winget.Name) { $Target.Name = $Winget.Name }
    if (-not $Target.Version) { $Target.Version = $Winget.Version }
}
