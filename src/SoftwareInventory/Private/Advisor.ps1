# KI-Berater: Tools, die ein Sprachmodell aufrufen darf. Sie lesen nur Daten oder erzeugen
# Vorschläge; ausgeführt wird nie etwas (das bestätigt der Benutzer in der Oberfläche).
# Jede Antwort an das Modell läuft durch Protect-PrivateText (Benutzerpfade, Namen, Schlüssel).
# Texte stehen in SoftwareInventory.Strings.psd1; hier nur ihre Schlüssel (siehe CLAUDE.md).

$script:AdvisorContext = $null          # Bewertungen (SecurityRating) aus dem letzten Scan
$script:AdvisorMaxListItems = 200

$script:AdvisorIdProperty = [ordered]@{ id = @{ type = 'string'; Text = 'AdvisorParamId' } }
$script:AdvisorProposalProperties = [ordered]@{
    id     = @{ type = 'string'; Text = 'AdvisorParamId' }
    reason = @{ type = 'string'; Text = 'AdvisorParamReason' }
}
$script:AdvisorTools = [ordered]@{
    get_inventory          = @{
        Kind = 'Read'; Text = 'AdvisorToolGetInventory'; Required = @()
        Properties = [ordered]@{
            filter       = @{ type = 'string'; Text = 'AdvisorParamFilter' }
            rating       = @{ type = 'string'; enum = @('Red', 'Yellow', 'Gray', 'Green'); Text = 'AdvisorParamRating' }
            updates_only = @{ type = 'boolean'; Text = 'AdvisorParamUpdatesOnly' }
            limit        = @{ type = 'integer'; minimum = 1; maximum = 200; Text = 'AdvisorParamLimit' }
        }
    }
    get_program_details    = @{ Kind = 'Read'; Text = 'AdvisorToolGetProgramDetails'; Required = @('id'); Properties = $script:AdvisorIdProperty }
    check_latest_version   = @{ Kind = 'Read'; Text = 'AdvisorToolCheckLatestVersion'; Required = @('id'); Properties = $script:AdvisorIdProperty }
    search_vulnerabilities = @{ Kind = 'Read'; Text = 'AdvisorToolSearchVulnerabilities'; Required = @('id'); Properties = $script:AdvisorIdProperty }
    propose_update         = @{ Kind = 'Proposal'; Text = 'AdvisorToolProposeUpdate'; Required = @('id', 'reason'); Properties = $script:AdvisorProposalProperties }
    propose_uninstall      = @{ Kind = 'Proposal'; Text = 'AdvisorToolProposeUninstall'; Required = @('id', 'reason'); Properties = $script:AdvisorProposalProperties }
}

function ConvertTo-AdvisorSchema {
    # JSON-Schema der Parameter eines Tools, Beschreibungen in der aktuellen Sprache.
    param($Tool)
    $properties = [ordered]@{}
    foreach ($name in $Tool.Properties.Keys) {
        $p = $Tool.Properties[$name]
        $schema = [ordered]@{ type = $p.type }
        foreach ($key in 'enum', 'minimum', 'maximum') { if ($p.ContainsKey($key)) { $schema[$key] = $p[$key] } }
        $schema.description = Get-LocalizedString $p.Text
        $properties[$name] = $schema
    }
    [ordered]@{ type = 'object'; properties = $properties; required = @($Tool.Required) }
}

function Get-AdvisorProgramId {
    # Kurze, neutrale Kennung ohne persönliche Angaben (Hash des stabilen Schlüssels).
    param($Record)
    $identity = Get-RecordIdentity $Record
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($identity)))
    'p-' + $hash.Substring(0, 12).ToLowerInvariant()
}

function Get-AdvisorContextRating {
    # Bewertungen aus dem letzten Scan; ohne App wird einmal eingelesen.
    if ($null -eq $script:AdvisorContext) {
        $script:AdvisorContext = @(Get-SoftwareInventory | Get-SecurityRating)
    }
    $script:AdvisorContext
}

function Find-AdvisorRating {
    param([string] $Id)
    Get-AdvisorContextRating | Where-Object { (Get-AdvisorProgramId $_.Record) -eq $Id } | Select-Object -First 1
}

function ConvertTo-AdvisorSummary {
    # Kurzfassung eines Programms für Listen.
    param($Rating)
    $v = $Rating.VulnerabilityStatus
    $counted = @(if ($v) { $v.Vulnerabilities | Where-Object { $_.Assessment -in 'Affected', 'PossiblyAffected' } })
    [ordered]@{
        id                = Get-AdvisorProgramId $Rating.Record
        name              = $Rating.Name
        publisher         = Get-RecordValue $Rating.Record 'Publisher'
        version           = $Rating.Version
        latest_version    = $Rating.LatestVersion
        update_available  = [bool] ($Rating.UpdateStatus -and $Rating.UpdateStatus.Status -eq 'Outdated')
        rating            = $Rating.Rating
        vulnerabilities   = if ($v -and ($v.Status -eq 'Checked' -or $counted)) { $counted.Count } else { $null }
        possibly_affected = @($counted | Where-Object Assessment -eq 'PossiblyAffected').Count
        reasons           = @(ConvertTo-MessageData @($Rating.Reasons | Select-Object -First 3))
    }
}

function ConvertTo-AdvisorDetail {
    param($Rating)
    $detail = ConvertTo-AdvisorSummary $Rating
    $record = $Rating.Record
    $v = $Rating.VulnerabilityStatus
    $u = $Rating.UpdateStatus
    $detail.reasons = @(ConvertTo-MessageData @($Rating.Reasons))
    $detail.sources = @(Get-RecordValue $record 'Sources')
    $detail.install_type = Get-RecordValue $record 'InstallType'
    $detail.scope = Get-RecordValue $record 'Scope'
    $detail.winget_id = Get-RecordValue $record 'WingetId'
    $detail.latest_version_source = if ($u) { $u.Source } else { $null }
    $detail.latest_version_confirmed = if ($u -and $u.PSObject.Properties['Confirmed']) { [bool] $u.Confirmed } else { $null }
    $detail.vulnerability_check = if ($v) { [ordered]@{ status = $v.Status; reason = ConvertTo-MessageData $v.Reason; notes = @(ConvertTo-MessageData @($v.Notes)) } } else { $null }
    $detail.vulnerability_list = @(if ($v) {
            $v.Vulnerabilities | Select-Object -First 25 | ForEach-Object {
                [ordered]@{
                    cve         = $_.CveId
                    assessment  = $_.Assessment
                    kev         = [bool] $_.Kev
                    cvss        = $_.Score
                    epss        = $_.Epss
                    note        = ConvertTo-MessageData $_.Note
                    sources     = @(if ($_.PSObject.Properties['Sources']) { $_.Sources | ForEach-Object { [ordered]@{ source = $_.Source; verdict = $_.Verdict; range = $_.Range } } })
                    description = if ($_.Description -and $_.Description.Length -gt 400) { $_.Description.Substring(0, 400) + '…' } else { $_.Description }
                }
            }
        })
    $detail.refuted = @(if ($v -and $v.PSObject.Properties['Refuted']) { ConvertTo-MessageData @($v.Refuted | ForEach-Object Note) })
    $detail
}

function New-AdvisorToolResult {
    param([string] $Name, [bool] $Ok, $Data, $Proposal = $null, [string] $Code)
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.AdvisorToolResult'
        Name       = $Name
        Ok         = $Ok
        Code       = $Code    # Fehler- oder Statuscode, z. B. UnknownId oder ProposalCreated
        Content    = Protect-PrivateText ($Data | ConvertTo-Json -Depth 8 -Compress)
        Proposal   = $Proposal
    }
}

function New-AdvisorToolError {
    # Fehler für das Modell: fester Code plus Meldung in der aktuellen Sprache.
    param([string] $Name, [string] $Code, [object[]] $Arguments = @())
    New-AdvisorToolResult -Name $Name -Ok $false -Code $Code -Data ([ordered]@{
            error_code = $Code
            error      = Get-LocalizedString "AdvisorError$Code" $Arguments
        })
}
