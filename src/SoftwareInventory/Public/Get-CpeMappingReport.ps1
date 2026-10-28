function Get-CpeMappingReport {
    <#
    .SYNOPSIS
        Bereitet „Vorschlag melden“ vor: Link zu einem vorausgefüllten GitHub-Issue für eine bestätigte CPE-Zuordnung.
    .DESCRIPTION
        Nur für Zuordnungen, die der Benutzer mit Set-CpeMapping bestätigt hat. Das Issue
        enthält Programmname, Hersteller, winget-ID, Version und CPE; Benutzername,
        Rechnername und Benutzerpfade werden vorher ersetzt (Protect-PrivateText).
        Es wird nichts gesendet: Der Link öffnet das Formular im Browser, abgeschickt wird es
        nur vom Benutzer selbst, und das Issue ist öffentlich.
        Ohne bestätigte Zuordnung kommt eine Fehlermeldung mit dem Code NoUserCpeMapping.
    .EXAMPLE
        Get-SoftwareInventory | Where-Object Name -like 'GIMP*' | Get-CpeMappingReport | Select-Object -ExpandProperty Url
    #>
    [CmdletBinding()]
    [OutputType('SoftwareInventory.CpeMappingReport')]
    param([Parameter(Mandatory, ValueFromPipeline)] $InputObject)
    begin {
        $map = Read-CpeMapping
        $project = $MyInvocation.MyCommand.Module.PrivateData.PSData.ProjectUri
    }
    process {
        $record = if ($InputObject.PSObject.Properties['Record'] -and $InputObject.Record) { $InputObject.Record } else { $InputObject }
        $mapping = $map[(Get-CpeMappingKey $record)]
        if (-not $mapping) {
            $message = New-InventoryMessage NoUserCpeMapping $record.Name
            $exception = [System.InvalidOperationException]::new($message.Text)
            $exception.Data['Code'] = $message.Code
            Write-Error -Exception $exception -Category ObjectNotFound -TargetObject $record.Name
            return
        }
        $fields = [ordered]@{
            program   = Protect-PrivateText ([string] $record.Name)
            publisher = Protect-PrivateText ([string] $record.Publisher)
            'winget-id' = [string] $record.WingetId
            version   = Protect-PrivateText ([string] $record.Version)
            cpe       = (@($mapping.Cpe) -join "`n")
        }
        $title = Get-LocalizedString 'CpeReportTitle' $fields.program
        $query = @("template=cpe-zuordnung.yml", "title=$([uri]::EscapeDataString($title))") +
            @($fields.GetEnumerator() | Where-Object Value | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" })
        [pscustomobject] @{
            PSTypeName = 'SoftwareInventory.CpeMappingReport'
            Title      = $title
            Fields     = [pscustomobject] $fields
            Url        = "$project/issues/new?$($query -join '&')"
        }
    }
}
