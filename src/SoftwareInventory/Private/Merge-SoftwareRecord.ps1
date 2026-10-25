function Merge-SoftwareRecord {
    <#
    .SYNOPSIS
        Führt Registry-, Appx- und winget-Datensätze zu einem Datensatz pro Programm zusammen.
    .DESCRIPTION
        Registry und Appx bilden die Grundlage. winget-Datensätze werden über ihre
        Abgleichschlüssel (Registry-Schlüsselname, PackageFullName, PackageFamilyName)
        zugeordnet, ersatzweise über Name und Version. winget-Einträge mit Schlüsseln,
        aber ohne Gegenstück entfallen, da die Grundquellen sie bewusst ausgefiltert haben.
        Danach werden Begleitpakete (Sparse Packages) ihrem Programm zugeordnet, siehe
        Join-CompanionPackage.
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

    $records = @(@($BaseRecord) + $standalone | Where-Object { $null -ne $_ })
    Join-CompanionPackage -Record $records |
        ForEach-Object { $_.PSObject.Properties.Remove('MatchKeys'); $_.PSObject.Properties.Remove('CompanionInfo'); $_ } |
        Sort-Object Name
}

function Join-CompanionPackage {
    <#
    .SYNOPSIS
        Hängt Sparse Packages an das klassische Programm, zu dem sie gehören (Feld Companions).
    .DESCRIPTION
        Zuordnung nur, wenn sie eindeutig ist: genau ein Registry-Programm mit genau diesem Namen,
        sonst genau eines, dessen Name mit dem Anzeigenamen des Pakets beginnt, sonst genau eines,
        das ihn als ganze Wörter enthält
        („OneDrive“ in „Microsoft OneDrive“); ersatzweise genau eines mit demselben Hersteller.
        Sonst bleibt das Paket als eigener Eintrag mit Flag SparsePackage stehen
        (lieber ein Eintrag zu viel als ein übersehener).
    #>
    param([object[]] $Record)

    $programs = @($Record | Where-Object { $_.InstallType -ne 'MSIX' -and 'Registry' -in $_.Sources })
    $joined = [System.Collections.Generic.HashSet[object]]::new()
    foreach ($companion in $Record) {
        if (-not ($companion.PSObject.Properties['CompanionInfo'] -and $companion.Flags -contains 'SparsePackage')) { continue }
        $info = $companion.CompanionInfo
        $target = $null
        $ambiguous = $false
        :search foreach ($name in @($info.DisplayName, $companion.Name) | Where-Object { $_ } | Select-Object -Unique) {
            $escaped = [regex]::Escape($name)
            # Vom genauesten zum lockersten Vergleich; der erste eindeutige Treffer zählt.
            foreach ($pattern in "^$escaped$", "^$escaped(\W|$)", "(^|\W)$escaped(\W|$)") {
                $byName = @($programs | Where-Object { $_.Name -match $pattern })
                if ($byName.Count -eq 1) { $target = $byName[0]; break search }
                if ($byName.Count -gt 1) { $ambiguous = $true; break search }
            }
        }
        if (-not $target -and -not $ambiguous) {
            $publisher = ConvertTo-PublisherKey $(if ($info.PublisherDisplayName) { $info.PublisherDisplayName } else { $companion.Publisher })
            if ($publisher) {
                $byPublisher = @($programs | Where-Object { (ConvertTo-PublisherKey $_.Publisher) -eq $publisher })
                if ($byPublisher.Count -eq 1) { $target = $byPublisher[0] }
            }
        }
        if ($target) {
            $target.Companions = [string[]] @(@($target.Companions) + $companion.PackageFullName | Where-Object { $_ } | Select-Object -Unique)
            [void] $joined.Add($companion)
            Write-Verbose "Begleitpaket $($companion.PackageFullName) gehört zu $($target.Name)"
        }
    }
    $Record | Where-Object { -not $joined.Contains($_) }
}

function ConvertTo-PublisherKey {
    # Herstellername ohne Rechtsform und Satzzeichen, für den Vergleich ("Bitdefender SRL" = "Bitdefender").
    param([string] $Publisher)
    if (-not $Publisher) { return $null }
    $key = $Publisher.ToLowerInvariant() -replace '[^\p{L}\p{N} ]', ' '
    $key = $key -replace '\b(inc|llc|ltd|limited|gmbh|ag|srl|s r l|sa|bv|corp|corporation|co|company|pbc)\b', ' '
    $key = ($key -replace '\s+', ' ').Trim()
    if ($key) { $key } else { $null }
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
