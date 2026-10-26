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
