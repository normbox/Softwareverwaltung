# KI-Berater: Tools, die ein Sprachmodell aufrufen darf. Sie lesen nur Daten oder erzeugen
# Vorschläge; ausgeführt wird nie etwas (das bestätigt der Benutzer in der Oberfläche).
# Jede Antwort an das Modell läuft durch Protect-PrivateText (Benutzerpfade, Namen, Schlüssel).

$script:AdvisorContext = $null          # Bewertungen (SecurityRating) aus dem letzten Scan
$script:AdvisorMaxListItems = 200

$script:AdvisorTools = [ordered]@{
    get_inventory          = @{
        Kind        = 'Read'
        Description = 'Listet die installierten Programme aus dem letzten Scan mit Ampel, Versionen und Zahl der Sicherheitslücken. Filterbar; liefert je Programm eine id für die anderen Tools.'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{
                filter         = [ordered]@{ type = 'string'; description = 'Teil des Programm- oder Herstellernamens, z. B. "7-Zip". Leer = alle.' }
                rating         = [ordered]@{ type = 'string'; enum = @('Red', 'Yellow', 'Gray', 'Green'); description = 'Nur Programme mit dieser Ampel.' }
                updates_only   = [ordered]@{ type = 'boolean'; description = 'Nur Programme mit verfügbarem Update.' }
                limit          = [ordered]@{ type = 'integer'; minimum = 1; maximum = 200; description = 'Höchstzahl der Einträge (Standard 50).' }
            }
            required   = @()
        }
    }
    get_program_details    = @{
        Kind        = 'Read'
        Description = 'Details zu einem Programm: alle Gründe der Ampel, bekannte Sicherheitslücken (CVE, KEV, CVSS, EPSS), widerlegte Treffer, Installationsart und winget-ID.'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{ id = [ordered]@{ type = 'string'; description = 'id aus get_inventory, z. B. "p-1a2b3c4d5e6f".' } }
            required   = @('id')
        }
    }
    check_latest_version   = @{
        Kind        = 'Read'
        Description = 'Prüft jetzt neu, welche Version eines Programms die neueste ist (nur über die vom Benutzer aktivierten Dienste).'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{ id = [ordered]@{ type = 'string'; description = 'id aus get_inventory.' } }
            required   = @('id')
        }
    }
    search_vulnerabilities = @{
        Kind        = 'Read'
        Description = 'Sucht jetzt neu nach bekannten Sicherheitslücken eines Programms (NVD, CISA KEV, EPSS; nur die vom Benutzer aktivierten Dienste).'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{ id = [ordered]@{ type = 'string'; description = 'id aus get_inventory.' } }
            required   = @('id')
        }
    }
    propose_update         = @{
        Kind        = 'Proposal'
        Description = 'Schlägt dem Benutzer vor, ein Programm zu aktualisieren. Führt nichts aus: Der Benutzer sieht den Vorschlag als Karte und bestätigt selbst.'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{
                id     = [ordered]@{ type = 'string'; description = 'id aus get_inventory.' }
                reason = [ordered]@{ type = 'string'; description = 'Kurze Begründung für den Benutzer, auf Deutsch.' }
            }
            required   = @('id', 'reason')
        }
    }
    propose_uninstall      = @{
        Kind        = 'Proposal'
        Description = 'Schlägt dem Benutzer vor, ein Programm zu deinstallieren. Führt nichts aus: Der Benutzer sieht den Vorschlag als Karte und bestätigt selbst.'
        Parameters  = [ordered]@{
            type       = 'object'
            properties = [ordered]@{
                id     = [ordered]@{ type = 'string'; description = 'id aus get_inventory.' }
                reason = [ordered]@{ type = 'string'; description = 'Kurze Begründung für den Benutzer, auf Deutsch.' }
            }
            required   = @('id', 'reason')
        }
    }
}

$script:AdvisorSystemPrompt = @'
Du bist der Sicherheitsberater der Softwareverwaltung auf einem Windows-PC. Du antwortest auf Deutsch, knapp und in einfachen Worten.

Regeln:
- Stütze Aussagen über installierte Programme, Versionen und Sicherheitslücken nur auf Ergebnisse der Tools. Was die Tools nicht liefern, weißt du nicht; sag das.
- Hole dir zuerst mit get_inventory die Programme und ihre id, dann bei Bedarf Details mit get_program_details.
- Du führst nie etwas aus. Updates und Deinstallationen schlägst du nur mit propose_update oder propose_uninstall vor; der Benutzer bestätigt sie selbst in der App. Sag nie, dass etwas aktualisiert oder entfernt wurde.
- Ampel: Rot = aktiv ausgenutzte oder kritische Lücke, Gelb = andere Lücken, „möglicherweise betroffen“ oder Update verfügbar, Grün = geprüft ohne Befund, Grau = nicht geprüft (der Grund steht dabei).
- „Möglicherweise betroffen“ heißt: Die Version ließ sich nicht prüfen. Stelle das nicht als sicher dar.
- Platzhalter wie %USERPROFILE% oder %USERNAME% stehen für bereinigte persönliche Angaben; frage nicht danach.
'@

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
        id                    = Get-AdvisorProgramId $Rating.Record
        name                  = $Rating.Name
        publisher             = Get-RecordValue $Rating.Record 'Publisher'
        version               = $Rating.Version
        latest_version        = $Rating.LatestVersion
        update_available      = [bool] ($Rating.UpdateStatus -and $Rating.UpdateStatus.Status -eq 'Outdated')
        rating                = $Rating.Rating
        vulnerabilities       = if ($v -and ($v.Status -eq 'Checked' -or $counted)) { $counted.Count } else { $null }
        possibly_affected     = @($counted | Where-Object Assessment -eq 'PossiblyAffected').Count
        reasons               = @($Rating.Reasons | Select-Object -First 3)
    }
}

function ConvertTo-AdvisorDetail {
    param($Rating)
    $detail = ConvertTo-AdvisorSummary $Rating
    $record = $Rating.Record
    $v = $Rating.VulnerabilityStatus
    $u = $Rating.UpdateStatus
    $detail.reasons = @($Rating.Reasons)
    $detail.sources = @(Get-RecordValue $record 'Sources')
    $detail.install_type = Get-RecordValue $record 'InstallType'
    $detail.scope = Get-RecordValue $record 'Scope'
    $detail.winget_id = Get-RecordValue $record 'WingetId'
    $detail.latest_version_source = if ($u) { $u.Source } else { $null }
    $detail.latest_version_confirmed = if ($u -and $u.PSObject.Properties['Confirmed']) { [bool] $u.Confirmed } else { $null }
    $detail.vulnerability_check = if ($v) { [ordered]@{ status = $v.Status; reason = $v.Reason; notes = @($v.Notes) } } else { $null }
    $detail.vulnerability_list = @(if ($v) {
            $v.Vulnerabilities | Select-Object -First 25 | ForEach-Object {
                [ordered]@{
                    cve         = $_.CveId
                    assessment  = $_.Assessment
                    kev         = [bool] $_.Kev
                    cvss        = $_.Score
                    epss        = $_.Epss
                    note        = $_.Note
                    description = if ($_.Description -and $_.Description.Length -gt 400) { $_.Description.Substring(0, 400) + '…' } else { $_.Description }
                }
            }
        })
    $detail.refuted = @(if ($v -and $v.PSObject.Properties['Refuted']) { $v.Refuted | ForEach-Object Note })
    $detail
}

function New-AdvisorToolResult {
    param([string] $Name, [bool] $Ok, $Data, $Proposal = $null)
    [pscustomobject] [ordered]@{
        PSTypeName = 'SoftwareInventory.AdvisorToolResult'
        Name       = $Name
        Ok         = $Ok
        Content    = Protect-PrivateText ($Data | ConvertTo-Json -Depth 8 -Compress)
        Proposal   = $Proposal
    }
}
