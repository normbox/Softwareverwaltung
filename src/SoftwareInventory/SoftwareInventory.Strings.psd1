# Texte des Moduls (Basissprache Deutsch). Geladen mit Import-LocalizedData, abgerufen mit
# Get-LocalizedString. Weitere Sprachen später als Unterordner, z. B. en-US\SoftwareInventory.Strings.psd1
# mit denselben Schlüsseln. Platzhalter {0}, {1} … wie bei -f.
@{
    # KI-Berater: Systemanweisung für das Modell
    AdvisorSystemPrompt                     = @'
Du bist der Sicherheitsberater der Softwareverwaltung auf einem Windows-PC. Du antwortest auf Deutsch, knapp und in einfachen Worten.

Regeln:
- Stütze Aussagen über installierte Programme, Versionen und Sicherheitslücken nur auf Ergebnisse der Tools. Was die Tools nicht liefern, weißt du nicht; sag das.
- Hole dir zuerst mit get_inventory die Programme und ihre id, dann bei Bedarf Details mit get_program_details.
- Du führst nie etwas aus. Updates und Deinstallationen schlägst du nur mit propose_update oder propose_uninstall vor; der Benutzer bestätigt sie selbst in der App. Sag nie, dass etwas aktualisiert oder entfernt wurde.
- Ampel: Red = aktiv ausgenutzte oder kritische Lücke, Yellow = andere Lücken, „möglicherweise betroffen“ oder Update verfügbar, Green = geprüft ohne Befund, Gray = nicht geprüft (der Grund steht dabei).
- „Möglicherweise betroffen“ (PossiblyAffected) heißt: Die Version ließ sich nicht prüfen. Stelle das nicht als sicher dar.
- Fehler der Tools haben ein Feld error_code; korrigiere den Aufruf oder erkläre dem Benutzer, was fehlt.
- Platzhalter wie %USERPROFILE%, %USERNAME% oder %OTHERUSER% stehen für bereinigte persönliche Angaben; frage nicht danach.
'@

    # KI-Berater: Tool-Beschreibungen
    AdvisorToolGetInventory                 = 'Listet die installierten Programme aus dem letzten Scan mit Ampel, Versionen und Zahl der Sicherheitslücken. Filterbar; liefert je Programm eine id für die anderen Tools.'
    AdvisorToolGetProgramDetails            = 'Details zu einem Programm: alle Gründe der Ampel, bekannte Sicherheitslücken (CVE, KEV, CVSS, EPSS), widerlegte Treffer, Installationsart und winget-ID.'
    AdvisorToolCheckLatestVersion           = 'Prüft jetzt neu, welche Version eines Programms die neueste ist (nur über die vom Benutzer aktivierten Dienste).'
    AdvisorToolSearchVulnerabilities        = 'Sucht jetzt neu nach bekannten Sicherheitslücken eines Programms (NVD, CISA KEV, EPSS; nur die vom Benutzer aktivierten Dienste).'
    AdvisorToolProposeUpdate                = 'Schlägt dem Benutzer vor, ein Programm zu aktualisieren. Führt nichts aus: Der Benutzer sieht den Vorschlag als Karte und bestätigt selbst.'
    AdvisorToolProposeUninstall             = 'Schlägt dem Benutzer vor, ein Programm zu deinstallieren. Führt nichts aus: Der Benutzer sieht den Vorschlag als Karte und bestätigt selbst.'
    AdvisorParamFilter                      = 'Teil des Programm- oder Herstellernamens, z. B. "7-Zip". Leer = alle.'
    AdvisorParamRating                      = 'Nur Programme mit dieser Ampel.'
    AdvisorParamUpdatesOnly                 = 'Nur Programme mit verfügbarem Update.'
    AdvisorParamLimit                       = 'Höchstzahl der Einträge (Standard 50).'
    AdvisorParamId                          = 'id aus get_inventory, z. B. "p-1a2b3c4d5e6f".'
    AdvisorParamReason                      = 'Kurze Begründung für den Benutzer.'

    # KI-Berater: Fehler (Schlüssel = AdvisorError + error_code)
    AdvisorErrorUnknownTool                 = 'Unbekanntes Tool ''{0}''. Verfügbar: {1}.'
    AdvisorErrorInvalidArguments            = 'Die Argumente sind kein gültiges JSON-Objekt.'
    AdvisorErrorInvalidId                   = 'Ungültige id ''{0}''. Erst get_inventory aufrufen und die dortige id verwenden.'
    AdvisorErrorUnknownId                   = 'Kein Programm mit id ''{0}'' im letzten Scan. Erst get_inventory aufrufen.'
    AdvisorErrorInvalidLimit                = 'limit muss zwischen 1 und {0} liegen.'
    AdvisorErrorInvalidRating               = 'rating muss Red, Yellow, Gray oder Green sein.'
    AdvisorErrorReasonMissing               = 'reason fehlt: Begründung für den Benutzer angeben.'
    AdvisorErrorNoUpdateKnown               = 'Für ''{0}'' ist kein Update bekannt. Erst check_latest_version aufrufen.'
    AdvisorErrorToolFailed                  = 'Fehler bei {0}: {1}'

    # KI-Berater: Status (Schlüssel = AdvisorStatus + status_code)
    AdvisorStatusProposalCreated            = 'Vorschlag wird dem Benutzer angezeigt. Nichts wurde ausgeführt; der Benutzer entscheidet selbst.'

    # KI-Berater: Kontext
    AdvisorContextTarget                    = 'KI-Berater'
    AdvisorContextAction                    = 'Daten des letzten Scans übernehmen'

    # KI-Berater: Hinweise zu den Server-Vorgaben (Schlüssel = AdvisorPresetNote + Name)
    AdvisorPresetNoteLMStudio               = 'Lokalen Server in LM Studio starten (Developer → Start Server).'
    AdvisorPresetNoteUnsloth                = 'Braucht einen API-Schlüssel (sk-unsloth-…) aus den Einstellungen von Unsloth Studio. Der Port ist nicht fest (oft 8888, manchmal 8000).'
    AdvisorPresetNoteCustom                 = 'Jeder Server mit OpenAI-kompatibler Schnittstelle und Tool-Unterstützung (/v1/chat/completions mit tools).'
    AdvisorPresetLabelCustom                = 'Eigene Adresse'

    # Einstellungen (Schlüssel = SettingsError + Code)
    SettingsErrorInvalidAdvisorEndpoint     = 'Ungültige Adresse ''{0}'': erwartet wird http:// oder https:// ohne Benutzerdaten, z. B. http://localhost:11434/v1.'
}
