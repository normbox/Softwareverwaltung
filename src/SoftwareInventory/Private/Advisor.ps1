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
    # Bewertungen aus dem letzten Scan (Set-AdvisorContext). Das Modul liest nie selbst ein: Ein Scan fragt
    # externe Dienste ab und startet nur auf Wunsch des Benutzers. Ohne Kontext antworten die Tools mit NoScanData.
    if ($null -eq $script:AdvisorContext) { return @() }
    $script:AdvisorContext
}

function Test-AdvisorContext {
    # Gibt es Daten aus einem Scan? Auch ein Scan ohne Programme zählt.
    $null -ne $script:AdvisorContext
}

function Find-AdvisorRating {
    # Programm über die id, nur unter den Programmen, die die Freigabestufe zeigt.
    param([string] $Id, [int] $Level = 3)
    Get-AdvisorVisibleRating -Level $Level | Where-Object { (Get-AdvisorProgramId $_.Record) -eq $Id } | Select-Object -First 1
}

# --- Freigabestufen ---------------------------------------------------------------------------
# Stufe 0 Übersicht, 1 Programmliste, 2 Installationsdetails, 3 portable Programme (nur Funde der
# Dateisuche), 4 Nutzungsspuren vergröbert. Was eine Stufe nicht zeigt, erreicht das Modell nie;
# die Grenze setzen diese Funktionen, nicht der Prompt. Nie an die KI: Produktcode, Registry-Schlüssel,
# Deinstallationsbefehle, Symbol, Begleitpakete, Paketnamen, Hash, weitere Fundorte, Pfad portabler
# Programme, Installationsdatum, genaue Zeitstempel, Startzähler und die Art der Spur.

$script:AdvisorMaxCveIds = 200
# Merkmale portabler Programme, die ab Stufe 3 mitgehen (Autostart erst ab Stufe 4 als eigenes Feld)
$script:AdvisorPortableFlags = [ordered]@{
    Unsigned          = 'unsigned'
    InvalidSignature  = 'invalid_signature'
    InDownloadsOrTemp = 'in_downloads_or_temp'
    MultipleVersions  = 'multiple_versions'
}

function Get-AdvisorShareLimit {
    # Höchste erlaubte Freigabestufe je Anbieterart. Etappe 6: eine Richtlinie kann sie hier nur senken.
    param([ValidateSet('Local', 'External')] [string] $ProviderKind)
    [int] $script:AdvisorShareLevelMax[$ProviderKind]
}

function Get-AdvisorShareLevel {
    # Wirksame Stufe: Einstellung des Benutzers, höchstens die Grenze der Anbieterart.
    param([ValidateSet('Local', 'External')] [string] $ProviderKind, $Setting = (Read-InventorySetting))
    $configured = $script:AdvisorShareLevelDefault[$ProviderKind]
    if ($Setting -and $Setting.Advisor -and $Setting.Advisor.PSObject.Properties['ShareLevel'] -and $Setting.Advisor.ShareLevel) {
        $value = $Setting.Advisor.ShareLevel.PSObject.Properties[$ProviderKind]
        if ($value -and $null -ne ($value.Value -as [int])) { $configured = [int] $value.Value }
    }
    [Math]::Max(0, [Math]::Min($configured, (Get-AdvisorShareLimit -ProviderKind $ProviderKind)))
}

function Test-AdvisorPortable {
    # Portables Programm (Dateisuche oder Nutzungsspur) statt installiertem Programm?
    param($Record)
    (Get-RecordValue $Record 'InstallType') -eq 'Portable' -or 'Portable' -in @(Get-RecordValue $Record 'Sources') -or [bool] (Get-RecordValue $Record 'FilePath')
}

function Test-AdvisorVisible {
    # Zeigt die Stufe dieses Programm? Installierte ab Stufe 0 (in Anzahlen) bzw. 1, portable aus der
    # Dateisuche ab Stufe 3, portable nur über Nutzungsspuren erst ab Stufe 4 (ihr Fund hieße „wurde gestartet“).
    param($Record, [int] $Level)
    if (-not (Test-AdvisorPortable $Record)) { return $true }
    if ($Level -ge 4) { return $true }
    $Level -ge 3 -and 'FileScan' -in @(Get-RecordValue $Record 'Evidence')
}

function Get-AdvisorVisibleRating {
    param([int] $Level)
    @(Get-AdvisorContextRating) | Where-Object { $_ -and (Test-AdvisorVisible -Record $_.Record -Level $Level) }
}

function ConvertTo-AdvisorPath {
    # Bekannte Ordner als Platzhalter (z. B. %PROGRAMFILES%\7-Zip); Benutzerpfade ersetzt danach Protect-PrivateText.
    param([string] $Path)
    if (-not $Path) { return $null }
    $folders = [ordered]@{
        '%LOCALAPPDATA%'      = $env:LOCALAPPDATA
        '%APPDATA%'           = $env:APPDATA
        '%PROGRAMFILES(X86)%' = ${env:ProgramFiles(x86)}
        '%PROGRAMFILES%'      = $env:ProgramFiles
        '%WINDIR%'            = $env:windir
    }
    foreach ($name in $folders.Keys) {
        $folder = ([string] $folders[$name]).TrimEnd('\')
        if (-not $folder) { continue }
        if ($Path.Equals($folder, [StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith("$folder\", [StringComparison]::OrdinalIgnoreCase)) {
            return $name + $Path.Substring($folder.Length)
        }
    }
    $Path
}

function Get-AdvisorDriveType {
    # Laufwerksart (Removable, Network, Fixed …) oder $null; eigene Funktion, damit Tests sie vorgeben können.
    param([string] $Root)
    try { [string] ([System.IO.DriveInfo]::new($Root)).DriveType } catch { $null }
}

function Get-AdvisorLocationKind {
    <#
    .SYNOPSIS
        Art des Fundorts eines portablen Programms als feste Klasse statt Pfad.
    .OUTPUTS
        Downloads, Desktop, Documents, Temp, AppData, ProgramFiles, UserProfile, RemovableDrive,
        NetworkDrive, OtherDrive oder Other.
    #>
    param([string] $Path)
    if (-not $Path) { return 'Other' }
    if ($Path.StartsWith('\\')) { return 'NetworkDrive' }
    $userProfile = $env:USERPROFILE
    $known = [ordered]@{
        Temp         = @($env:TEMP, $env:TMP, (Join-Path ([string] $env:windir) 'Temp'))
        Downloads    = @($(if ($userProfile) { Join-Path $userProfile 'Downloads' }))
        Desktop      = @([Environment]::GetFolderPath('Desktop'))
        Documents    = @([Environment]::GetFolderPath('MyDocuments'))
        AppData      = @($env:LOCALAPPDATA, $env:APPDATA)
        ProgramFiles = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
        UserProfile  = @($userProfile)
    }
    foreach ($kind in $known.Keys) {
        foreach ($folder in $known[$kind]) {
            $f = ([string] $folder).TrimEnd('\')
            if ($f -and $Path.StartsWith("$f\", [StringComparison]::OrdinalIgnoreCase)) { return $kind }
        }
    }
    if ($Path -match '^[A-Za-z]:') {
        $root = $Path.Substring(0, 2) + '\'
        switch (Get-AdvisorDriveType $root) {
            'Removable' { return 'RemovableDrive' }
            'Network' { return 'NetworkDrive' }
        }
        $system = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
        if (-not $Path.StartsWith($system, [StringComparison]::OrdinalIgnoreCase)) { return 'OtherDrive' }
    }
    'Other'
}

function Get-AdvisorLastUsedClass {
    # Grobe Klasse statt Zeitstempel: within_1_month, 1_to_6_months, older oder unknown (keine Daten;
    # fehlende Spuren heißen nicht „nie genutzt“).
    param($LastRun, [datetime] $Now = [datetime]::UtcNow)
    if (-not $LastRun) { return 'unknown' }
    $when = [datetime]::MinValue
    if ($LastRun -is [datetime]) { $when = $LastRun.ToUniversalTime() }
    elseif (-not [datetime]::TryParse([string] $LastRun, [cultureinfo]::InvariantCulture, 'AssumeUniversal, AdjustToUniversal', [ref] $when)) { return 'unknown' }
    $days = ($Now - $when).TotalDays
    if ($days -le 31) { return 'within_1_month' }
    if ($days -le 183) { return '1_to_6_months' }
    'older'
}

function ConvertTo-AdvisorOverview {
    # Stufe 0: nur Anzahlen, Ampelverteilung und CVE-Nummern ohne Programmzuordnung.
    param([object[]] $Rating)
    $ratings = [ordered]@{ Red = 0; Yellow = 0; Gray = 0; Green = 0 }
    $cves = [System.Collections.Generic.List[string]]::new()
    $vulnCount = 0
    $kev = 0
    foreach ($r in $Rating) {
        if ($ratings.Contains([string] $r.Rating)) { $ratings[[string] $r.Rating]++ }
        $v = $r.VulnerabilityStatus
        foreach ($x in @(if ($v) { $v.Vulnerabilities }) | Where-Object { $_ -and $_.Assessment -in 'Affected', 'PossiblyAffected' }) {
            $vulnCount++
            if ($x.Kev) { $kev++ }
            if (-not $cves.Contains($x.CveId)) { $cves.Add($x.CveId) }
        }
    }
    $sorted = @($cves | Sort-Object)
    [ordered]@{
        share_level       = 0
        programs_in_scan  = @($Rating).Count
        ratings           = $ratings
        updates_available = @($Rating | Where-Object { $_.UpdateStatus -and $_.UpdateStatus.Status -eq 'Outdated' }).Count
        vulnerabilities   = $vulnCount
        kev               = $kev
        cve_ids           = @($sorted | Select-Object -First $script:AdvisorMaxCveIds)
        cve_ids_truncated = $sorted.Count -gt $script:AdvisorMaxCveIds
    }
}

function ConvertTo-AdvisorSummary {
    # Kurzfassung eines Programms für Listen (ab Stufe 1, auf allen Stufen gleich).
    param($Rating)
    $v = $Rating.VulnerabilityStatus
    $counted = @(if ($v) { $v.Vulnerabilities | Where-Object { $_.Assessment -in 'Affected', 'PossiblyAffected' } })
    [ordered]@{
        id                = Get-AdvisorProgramId $Rating.Record
        kind              = if (Test-AdvisorPortable $Rating.Record) { 'portable' } else { 'installed' }
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
    # Details eines Programms im Umfang der Stufe (ab 1).
    param($Rating, [int] $Level = 3)
    $detail = ConvertTo-AdvisorSummary $Rating
    $record = $Rating.Record
    $v = $Rating.VulnerabilityStatus
    $u = $Rating.UpdateStatus
    $portable = Test-AdvisorPortable $record
    $detail.reasons = @(ConvertTo-MessageData @($Rating.Reasons))
    $detail.latest_version_source = if ($u) { $u.Source } else { $null }
    $detail.latest_version_confirmed = if ($u -and $u.PSObject.Properties['Confirmed']) { [bool] $u.Confirmed } else { $null }
    if ($Level -ge 2) {
        $detail.sources = @(Get-RecordValue $record 'Sources')
        $detail.install_type = Get-RecordValue $record 'InstallType'
        $detail.scope = Get-RecordValue $record 'Scope'
        $detail.architecture = Get-RecordValue $record 'Architecture'
        $detail.winget_id = Get-RecordValue $record 'WingetId'
        $detail.winget_source = Get-RecordValue $record 'WingetSource'
        # Pfad nur bei installierten Programmen; bei portablen nur die Art des Fundorts (Stufe 3)
        if (-not $portable) { $detail.install_location = ConvertTo-AdvisorPath ([string] (Get-RecordValue $record 'InstallLocation')) }
    }
    if ($Level -ge 3 -and $portable) {
        $detail.signature_status = Get-RecordValue $record 'SignatureStatus'
        $detail.signer = Get-RecordValue $record 'Signer'
        $detail.location_kind = Get-AdvisorLocationKind ([string] (Get-RecordValue $record 'FilePath'))
        $flags = @(Get-RecordValue $record 'Flags')
        $detail.flags = @($script:AdvisorPortableFlags.Keys | Where-Object { $_ -in $flags } | ForEach-Object { $script:AdvisorPortableFlags[$_] })
    }
    if ($Level -ge 4 -and $portable) {
        $detail.last_used = Get-AdvisorLastUsedClass (Get-RecordValue $record 'LastRun')
        $evidence = @(Get-RecordValue $record 'Evidence')
        $detail.autostart = [bool] ('Autostart' -in $evidence -or 'ScheduledTask' -in $evidence -or 'Autostart' -in @(Get-RecordValue $record 'Flags'))
    }
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
    # Lücken nur für andere Plattformen (zählen unter Windows nicht)
    $detail.otherPlatform = @(if ($v -and $v.PSObject.Properties['OtherPlatform']) { ConvertTo-MessageData @($v.OtherPlatform | ForEach-Object Note) })
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
