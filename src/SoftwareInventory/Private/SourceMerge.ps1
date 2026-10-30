# Angaben je Quelle (NVD, CIRCL) zu einer CVE und ihre Zusammenführung.
# Verdict: Affected, NotAffected, NotEvaluable oder Unknown (CVE in dieser Quelle nicht bekannt).
# Weight: Wirkung auf die Ampel – Affected, PossiblyAffected, Informational oder $null (keine).

$script:SourceUrl = @{
    NVD   = 'https://nvd.nist.gov/vuln/detail/{0}'
    CIRCL = 'https://vulnerability.circl.lu/vuln/{0}'
}

function New-SourceStatement {
    param(
        [Parameter(Mandatory)] [ValidateSet('NVD', 'CIRCL')] [string] $Source,
        [Parameter(Mandatory)] [ValidateSet('Affected', 'NotAffected', 'NotEvaluable', 'Unknown')] [string] $Verdict,
        [string] $CveId,
        [string] $Range,
        $Note,   # SoftwareInventory.Message oder $null
        [string] $Weight
    )
    if (-not $Weight -and $Verdict -eq 'Affected') { $Weight = 'Affected' }
    [pscustomobject] @{
        PSTypeName  = 'SoftwareInventory.SourceStatement'
        Source      = $Source
        Verdict     = $Verdict
        Range       = if ($Range) { $Range } else { $null }
        Note        = $Note
        Weight      = if ($Weight) { $Weight } else { $null }
        # Namensnennung (CC BY 4.0 bei den CVE-Datensätzen über CIRCL)
        Attribution = New-InventoryMessage "Attribution$Source"
        Url         = if ($CveId) { $script:SourceUrl[$Source] -f $CveId } else { $null }
    }
}

function Get-NvdRangeText {
    # Versionsbereiche der NVD-Konfiguration für das Produkt, z. B. „>= 9.11, < 26.01“.
    param($Cve, [string[]] $CpeBase)
    $texts = foreach ($base in $CpeBase) {
        foreach ($match in Get-CveProductMatch -Cve $Cve -CpeBase $base) {
            $exact = ($match.criteria -split '(?<!\\):')[5]
            if ($exact -notin '*', '-') { "= $($exact -replace '\\', '')"; continue }
            $range = [pscustomobject] @{
                Start = $match.PSObject.Properties['versionStartIncluding']?.Value ?? $match.PSObject.Properties['versionStartExcluding']?.Value
                StartIncluding = [bool] $match.PSObject.Properties['versionStartIncluding']?.Value
                End = $match.PSObject.Properties['versionEndIncluding']?.Value ?? $match.PSObject.Properties['versionEndExcluding']?.Value
                EndIncluding = [bool] $match.PSObject.Properties['versionEndIncluding']?.Value
                Exact = $null
            }
            Format-VersionRange $range
        }
    }
    (@($texts | Where-Object { $_ }) | Select-Object -Unique) -join '; '
}

function Get-NvdStatement {
    # Angabe der NVD zu einer CVE für Produkt und Version.
    param($Cve, [string[]] $CpeBase, [string] $Version)
    $check = Get-CveProductAssessment -Cve $Cve -CpeBase $CpeBase -Version $Version
    $range = Get-NvdRangeText -Cve $Cve -CpeBase $CpeBase
    if ($null -eq $check.Affected) {
        return New-SourceStatement -Source NVD -Verdict NotEvaluable -CveId $Cve.id -Note (New-InventoryMessage NvdNoProductData)
    }
    if (-not $check.Affected) { return New-SourceStatement -Source NVD -Verdict NotAffected -CveId $Cve.id -Range $range }
    if ($check.Unbounded) {
        $kind = Get-UnboundedAssessment -Cve $Cve
        return New-SourceStatement -Source NVD -Verdict NotEvaluable -CveId $Cve.id -Note $kind.Note -Weight $kind.Assessment
    }
    New-SourceStatement -Source NVD -Verdict Affected -CveId $Cve.id -Range $range
}

function Get-CirclStatement {
    # Angabe von CIRCL (CVE-Datensatz) für Produkt und Version; ohne auswertbare Angabe gilt die Altersregel.
    param($Record, [string[]] $CpeBase, [string] $Version)
    $id = [string] $Record.cveMetadata.cveId
    $check = Get-CirclAssessment -Record $Record -CpeBase $CpeBase -Version $Version
    if ($check.Verdict -ne 'NotEvaluable') { return New-SourceStatement -Source CIRCL -Verdict $check.Verdict -CveId $id -Range $check.Range }
    $kind = Get-UnboundedAssessment -Cve ([pscustomobject] @{ published = $Record.cveMetadata.PSObject.Properties['datePublished']?.Value })
    $note = if ($kind.Assessment -eq 'Informational') { New-InventoryMessage CirclLegacyData $script:UnboundedMaxAgeYears } else { New-InventoryMessage CirclNoVersionRange }
    New-SourceStatement -Source CIRCL -Verdict NotEvaluable -CveId $id -Range $check.Range -Note $note -Weight $kind.Assessment
}

function Merge-SourceStatement {
    <#
    .SYNOPSIS
        Führt die Angaben der Quellen zu einer CVE zusammen; $null, wenn keine Quelle einen Treffer meldet.
    .DESCRIPTION
        Eine Quelle „betroffen“, eine andere mit Versionsdaten „nicht betroffen“: kein Widerlegen,
        sondern möglicherweise betroffen mit SourcesDisagree. Sonst „betroffen“ vor „nicht betroffen“
        vor „nicht auswertbar“ (jung: möglicherweise betroffen, alt: nur Hinweis). Unbekannt zählt nicht.
    #>
    param([object[]] $Statement, [string] $CveId)
    $list = @($Statement | Where-Object { $_ })
    $affected = @($list | Where-Object Verdict -eq 'Affected')
    $notAffected = @($list | Where-Object Verdict -eq 'NotAffected')
    if ($affected -and $notAffected) {
        return [pscustomobject] @{ Assessment = 'PossiblyAffected'; Note = (New-InventoryMessage SourcesDisagree $CveId); Disagree = $true }
    }
    if ($affected) { return [pscustomobject] @{ Assessment = 'Affected'; Note = $null; Disagree = $false } }
    if ($notAffected) { return $null }
    foreach ($weight in 'PossiblyAffected', 'Informational') {
        $hit = $list | Where-Object Weight -eq $weight | Select-Object -First 1
        if ($hit) { return [pscustomobject] @{ Assessment = $weight; Note = $hit.Note; Disagree = $false } }
    }
    $null
}
