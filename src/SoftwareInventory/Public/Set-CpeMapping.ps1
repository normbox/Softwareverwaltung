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
