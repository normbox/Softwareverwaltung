function Set-CpeMapping {
    <#
    .SYNOPSIS
        Bestätigt die CPE-Zuordnung für ein Programm ohne Katalogeintrag.
    .DESCRIPTION
        Die Zuordnung gilt danach für Get-SoftwareVulnerability wie ein Katalogeintrag.
        Gespeichert unter %APPDATA%\SoftwareInventory\cpe-map.json. Ein Katalogeintrag mit CPE
        hat Vorrang. Vorschläge liefert Find-CpeCandidate.
    .EXAMPLE
        $gimp = Get-SoftwareInventory | Where-Object Name -like 'GIMP*'
        Set-CpeMapping -InputObject $gimp -Cpe 'cpe:2.3:a:gimp:gimp'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] $InputObject,
        [Parameter(Mandatory)]
        [ValidatePattern('^cpe:2\.3:[aho]:(\\.|[^:\\])+:(\\.|[^:\\])+$')]
        [string[]] $Cpe
    )
    process {
        $record = if ($InputObject.PSObject.Properties['Record'] -and $InputObject.Record) { $InputObject.Record } else { $InputObject }
        $map = Read-CpeMapping
        $key = Get-CpeMappingKey $record
        if (-not $PSCmdlet.ShouldProcess($record.Name, "CPE-Zuordnung $($Cpe -join ', ') speichern")) { return }
        $map[$key] = [pscustomobject] @{ Key = $key; Name = $record.Name; Cpe = [string[]] $Cpe; ConfirmedAt = [datetime]::UtcNow.ToString('o') }
        Write-CpeMapping -Map $map
        $map[$key]
    }
}

function Get-CpeMapping {
    <#
    .SYNOPSIS
        Zeigt die vom Benutzer bestätigten CPE-Zuordnungen.
    #>
    [CmdletBinding()]
    param()
    (Read-CpeMapping).Values | Sort-Object Key
}

function Remove-CpeMapping {
    <#
    .SYNOPSIS
        Entfernt eine bestätigte CPE-Zuordnung (über den Datensatz oder den Schlüssel aus Get-CpeMapping).
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Record')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Record')] $InputObject,
        [Parameter(Mandatory, ParameterSetName = 'Key')] [string] $Key
    )
    process {
        $map = Read-CpeMapping
        $target = if ($PSCmdlet.ParameterSetName -eq 'Key') { $Key.ToLowerInvariant() } else {
            $record = if ($InputObject.PSObject.Properties['Record'] -and $InputObject.Record) { $InputObject.Record } else { $InputObject }
            # Einträge aus Get-CpeMapping tragen ihren Schlüssel selbst
            if ($record.PSObject.Properties['Key'] -and $record.PSObject.Properties['Cpe']) { $record.Key } else { Get-CpeMappingKey $record }
        }
        if (-not $map.ContainsKey($target)) { Write-Warning "Keine CPE-Zuordnung für '$target'."; return }
        if ($PSCmdlet.ShouldProcess($target, 'CPE-Zuordnung entfernen')) {
            $map.Remove($target)
            Write-CpeMapping -Map $map
        }
    }
}
