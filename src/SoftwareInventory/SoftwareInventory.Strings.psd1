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

    # Fortschritt (Write-CheckProgress; Schlüssel + Counted = Text mit Zähler)
    ProgressCheckUpdates                    = 'Prüfe neueste Versionen'
    ProgressCheckUpdatesCounted             = 'Prüfe neueste Versionen ({0} von {1})'
    ProgressCheckVulnerabilities            = 'Prüfe Sicherheitslücken'
    ProgressCheckVulnerabilitiesCounted     = 'Prüfe Sicherheitslücken ({0} von {1})'
    ProgressLoadKev                         = 'Lade die Liste aktiv ausgenutzter Lücken (CISA KEV)'
    ProgressLoadEpss                        = 'Lade Ausnutzungswahrscheinlichkeiten (FIRST EPSS)'
    ProgressReadWinget                      = 'Lese die winget-Paketliste'
    ProgressFindFiles                       = 'Suche nach Programmdateien'
    ProgressCheckFiles                      = 'Prüfe Programmdateien'

    # Suche nach portablen Programmen (Invoke-InventoryScan)
    PortableSearchNoLocation                = 'Dateisuche: Keine Option „Wo suchen“ gewählt oder die gewählte Option hat keinen Eintrag, daher wurden keine Dateien durchsucht.'
    PortableSearchNoTrace                   = 'Nutzungsspuren sind eingeschaltet, aber keine der Spuren ist gewählt.'
    PortableSearchNothingSelected           = 'Suche nach portablen Programmen ist eingeschaltet, aber weder Nutzungsspuren noch Dateisuche. Es wurde nichts durchsucht.'
    PortableDriveNotConnected               = 'Laufwerk {0} ist nicht verbunden und wurde übersprungen.'
    PortableFolderNotFound                  = 'Ordner {0} wurde nicht gefunden und übersprungen.'

    # Gründe, Status und Hinweise (New-InventoryMessage; Schlüssel = Reason + Code). Args stehen in {0}, {1} ….
    # Ampel
    ReasonKevAffected                       = 'Aktiv ausgenutzte Lücke {0} (CISA KEV)'
    ReasonCriticalCvss                      = 'Kritische Lücke {0} (CVSS {1})'
    ReasonKnownVulnerabilities              = '{0} bekannte Lücke(n)'
    ReasonKnownVulnerabilitiesMaxCvss       = '{0} bekannte Lücke(n), höchster CVSS {1}'
    ReasonPossiblyAffected                  = 'Möglicherweise betroffen: {0} ({1})'
    ReasonPossiblyAffectedKev               = 'Möglicherweise betroffen: {0} (aktiv ausgenutzt, {1})'
    ReasonUpdateAvailable                   = 'Update verfügbar: {0} → {1} (Quelle {2})'
    ReasonUpdateAvailableUnconfirmed        = 'Update verfügbar: {0} → {1} (Quelle {2}, unbestätigt)'
    ReasonNoFindings                        = 'Sicherheitsprüfung ohne Befund'
    ReasonVersionCurrent                    = 'Version aktuell'
    ReasonNotChecked                        = 'Nicht auf Lücken geprüft'
    ReasonNotCheckedBecause                 = 'Nicht auf Lücken geprüft: {0}'
    ReasonVersionUnknownBecause             = 'Versionsstand unbekannt: {0}'
    ReasonPathUnreachable                   = 'Pfad nicht erreichbar: Das Laufwerk ist gerade nicht verbunden (z. B. abgezogener USB-Stick). Gefunden über Nutzungsspuren.'

    # Dienste (Args: Name des Dienstes, ggf. Fehlermeldung)
    ReasonServiceDisabled                   = 'Dienst {0} nicht aktiviert'
    ReasonServiceUnavailable                = '{0} nicht abrufbar: {1}'
    ReasonRateLimit                         = '{0}-Anfragelimit erreicht'

    # Sicherheitslücken
    ReasonNoCpe                             = 'Keine CPE zugeordnet (kein Katalogeintrag, keine bestätigte Zuordnung; Vorschläge: Find-CpeCandidate)'
    ReasonNoCpeKevOnly                      = 'Keine CPE zugeordnet (nur KEV-Zuordnung im Katalog)'
    ReasonVersionUnreadable                 = 'Version ''{0}'' nicht lesbar'
    ReasonNvdNoVersionRange                 = 'Versionsbereich in der NVD nicht angegeben'
    ReasonNvdLegacyData                     = 'Altdaten ohne Versionsangabe in der NVD (älter als {0} Jahre); ohne Ampelwirkung'
    ReasonKevNvdNoVersionData               = 'Version nicht prüfbar (NVD ohne Versionsdaten)'
    ReasonKevNvdUnavailable                 = 'Version nicht prüfbar (NVD nicht abrufbar)'
    ReasonKevNvdDisabled                    = 'Version nicht prüfbar (Dienst NVD nicht aktiviert)'
    ReasonKevFixedInCatalog                 = 'behoben ab {0} (Katalog)'
    ReasonKevRefutedNvd                     = 'KEV-Treffer {0} widerlegt: Version {1} laut NVD nicht betroffen'
    ReasonKevRefutedCatalog                 = 'KEV-Treffer {0} widerlegt: behoben ab {1} (Katalog), installiert {2}'

    # Neueste Version
    ReasonNoVersionSource                   = 'Keine Versionsquelle bekannt (kein winget-Paket, kein Katalogeintrag)'
    ReasonNoLatestVersion                   = '{0}'
    ReasonInstalledNewer                    = 'Installierte Version ist neuer als die gefundene'
    ReasonInstalledVersionUnreadable        = 'Installierte Version ''{0}'' nicht lesbar'
    ReasonFoundVersionUnreadable            = 'Gefundene Version ''{0}'' nicht lesbar'
    ReasonGitHubNoRelease                   = 'Kein Release in {0} gefunden'
    ReasonGitHubTagMismatch                 = 'Release-Tag ''{0}'' passt nicht zum Katalogmuster'
    ReasonStoreApp                          = 'Store-App: Updates über den Microsoft Store'
    ReasonWingetSearchUnavailable           = 'winget-Suche nicht verfügbar ({0})'
    ReasonWingetSearchNoPublisher           = 'winget-Suche braucht einen Hersteller'
    ReasonWingetSearchFailed                = 'winget-Suche fehlgeschlagen: {0}'
    ReasonWingetSearchAmbiguous             = 'winget-Suche mehrdeutig'
    ReasonWingetSearchAmbiguousCount        = 'winget-Suche mehrdeutig ({0} Pakete mit passendem Namen)'
    ReasonWingetSearchNoMatch               = 'Kein passendes winget-Paket gefunden'
    ReasonWingetSearchImplausible           = 'winget-Treffer unplausibel (installiert {0}, gefunden {1})'

    # Aktionen: Planung
    ReasonActionVerbUpdate                  = 'Aktualisieren'
    ReasonActionVerbUninstall               = 'Deinstallieren'
    ReasonPlanDescription                   = '{0} über {1} {2}{3}: {4}'
    ReasonPlanRightsElevated                = 'mit Administratorrechten (UAC)'
    ReasonPlanRightsNormal                  = 'ohne Administratorrechte'
    ReasonPlanRestorePointFirst             = ', vorher Wiederherstellungspunkt'
    ReasonPlanNotInstalled                  = 'Das Programm ist nicht (mehr) installiert; es wurde nichts ausgeführt.'
    ReasonPlanManualUpdateLink              = 'Kein winget-Paket bekannt. Update bitte manuell über den Hersteller: {0}'
    ReasonPlanManualUpdateNoLink            = 'Kein winget-Paket bekannt. Update bitte manuell über den Hersteller; kein Link bekannt.'
    ReasonPlanUpdateOnlyWinget              = 'Aktualisieren geht nur über winget.'
    ReasonPlanNoUninstallMethod             = 'Keine Deinstallationsmethode bekannt (kein winget-Paket, kein MSI, keine Store-App, kein Deinstallationsbefehl).'
    ReasonPlanMethodNotAvailable            = 'Methode {0} ist für dieses Programm nicht verfügbar (verfügbar: {1}).'
    ReasonPlanInvalidWingetId               = 'Ungültige winget-ID oder -Quelle.'
    ReasonPlanWingetNotFound                = 'winget wurde nicht gefunden (App Installer fehlt).'
    ReasonPlanUninstallerUserWritable       = 'Das Deinstallationsprogramm liegt an einem für Benutzer beschreibbaren Ort ({0}) und wird aus Sicherheitsgründen nicht mit Administratorrechten gestartet. Bitte manuell deinstallieren.'
    ReasonCommandEmpty                      = 'Leere Befehlszeile'
    ReasonCommandUnclosedQuote              = 'Anführungszeichen nicht geschlossen'
    ReasonCommandNoExe                      = 'Kein Programm (.exe) in der Befehlszeile'
    ReasonCommandInterpreter                = 'Befehl startet einen Interpreter ({0}); aus Sicherheitsgründen nicht unterstützt, bitte manuell deinstallieren'
    ReasonCommandFileNotFound               = 'Programmdatei nicht gefunden: {0}'

    # Aktionen: Ausführung und Ergebnis
    ReasonNotConfirmed                      = 'Nicht bestätigt; es wurde nichts ausgeführt.'
    ReasonCommandChanged                    = 'Der Befehl hat sich seit der Bestätigung geändert; es wurde nichts ausgeführt. Bitte neu bestätigen. Jetzt: {0}'
    ReasonAppxRemoved                       = 'Store-App entfernt'
    ReasonAppxRemoveFailed                  = 'Store-App konnte nicht entfernt werden: {0}'
    ReasonActionTimeout                     = 'Keine Rückmeldung nach {0} Minuten; das Programm läuft eventuell noch. Zustand später prüfen.'
    ReasonUnexpectedError                   = 'Unerwarteter Fehler: {0}'
    ReasonNotVerifiedUninstall              = 'Das Programm meldet Erfolg, ist aber noch installiert.'
    ReasonNotVerifiedUpdate                 = 'Das Programm meldet Erfolg, die Version hat sich aber nicht erhöht.'
    ReasonWithNextMethod                    = '{0} Nächste mögliche Methode: {1} (Aufruf mit -Method {1}).'
    ReasonActionIncomplete                  = 'Kein Abschluss protokolliert: Die Aktion läuft noch oder wurde unterbrochen.'
    ReasonLegacyText                        = '{0} (älterer Eintrag)'

    # Aktionen: Wiederherstellungspunkt (Codes kommen auch vom erhöhten Helfer)
    ReasonRestorePointName                  = 'Softwareverwaltung: {0} {1}'
    ReasonRestorePointContinueWithout       = '{0} Die Aktion wird ohne Wiederherstellungspunkt fortgesetzt.'
    ReasonRestorePointServiceUnavailable    = 'Systemwiederherstellung nicht verfügbar: {0}'
    ReasonRestorePointProtectionOffDetail   = 'Computerschutz ist ausgeschaltet oder der Dienst deaktiviert: {0}'
    ReasonRestorePointProtectionOff         = 'Computerschutz ist ausgeschaltet oder der Dienst deaktiviert'
    ReasonRestorePointProtectionDisabled    = 'Computerschutz ist ausgeschaltet'
    ReasonRestorePointFailedDetail          = 'Wiederherstellungspunkt fehlgeschlagen: {0} (Codes: {1})'
    ReasonRestorePointFailedCode            = 'Wiederherstellungspunkt fehlgeschlagen (Code {0})'
    ReasonRestorePointCreatedNumber         = 'Wiederherstellungspunkt angelegt (Nr. {0})'
    ReasonRestorePointNotCreated            = 'Windows hat keinen neuen Punkt angelegt; meist, weil in den letzten 24 Stunden schon einer angelegt wurde'

    # Aktionen: erhöhter Helfer
    ReasonElevationDenied                   = 'Die Administratorabfrage (UAC) wurde abgelehnt.'
    ReasonHelperStartFailed                 = 'Erhöhter Prozess konnte nicht gestartet werden: {0}'
    ReasonHelperExitedWithoutResult         = 'Helfer ohne Ergebnis beendet (Exit-Code {0})'
    ReasonHelperNoResponse                  = 'Zeitüberschreitung: Der Helfer hat sich nicht gemeldet'
    ReasonHelperUnexpectedProcess           = 'Unerwarteter Prozess an der Ergebnis-Pipe; Ergebnis verworfen.'
    ReasonHelperResultIncomplete            = 'Ergebnis des Helfers unvollständig (Zeitüberschreitung beim Lesen).'
    ReasonHelperResultUnreadable            = 'Ergebnis des Helfers nicht lesbar.'
    ReasonHelperNonceMismatch               = 'Ergebnis gehört nicht zu dieser Aktion; verworfen.'
    ReasonHelperPathNotAbsolute             = 'Programmpfad fehlt oder ist nicht absolut'
    ReasonHelperWingetNotFound              = 'winget wurde im Administratorkontext nicht gefunden ({0})'
    ReasonHelperPathInUserFolder            = 'Programm liegt in einem Benutzer- oder Temp-Ordner ({0})'
    ReasonHelperFileNotFound                = 'Programmdatei nicht gefunden: {0}'
    ReasonHelperException                   = '{0}'

    # winget
    ReasonWingetInstallDescription          = 'Lädt die neueste Version von App Installer (winget) bei Microsoft herunter und installiert sie für dieses Benutzerkonto, ohne Administratorrechte: {0}'
    ReasonWingetInstallModuleMissing        = 'Das PowerShell-Modul Microsoft.WinGet.Client fehlt; winget lässt sich so nicht installieren. App Installer gibt es im Microsoft Store.'
    ReasonWingetInstalled                   = 'winget ist installiert und nutzbar.'
    ReasonWingetInstallNotVerified          = 'Repair-WinGetPackageManager ist durchgelaufen, winget ist aber noch nicht nutzbar: {0}'
    ReasonWingetInstallFailed               = 'winget konnte nicht installiert werden: {0}'
    ReasonWingetStatusMissing               = 'winget ist nicht verfügbar. Das Inventar kommt nur aus Registry und Store-Apps; Aktualisieren über winget ist nicht möglich.'
    ReasonWingetStatusCliMissing            = 'winget.exe (App Installer) fehlt. Aktualisieren und Deinstallieren über winget ist nicht möglich; andere Methoden bleiben nutzbar.'
    ReasonWingetStatusModuleMissing         = 'Das PowerShell-Modul Microsoft.WinGet.Client fehlt. Das Inventar enthält keine winget-Daten und keine verfügbaren Updates.'
    ReasonWingetClientModuleMissing         = 'Modul Microsoft.WinGet.Client ist nicht installiert'
    ReasonWingetClientNotInstalled          = 'winget (App Installer) ist nicht installiert'
    ReasonWingetDataUnavailable             = 'winget-Daten nicht verfügbar: {0}'

    # Exit-Codes (ConvertFrom-ActionExitCode; Schlüssel = ReasonExitCode + Schreibweise aus Format-ExitCode)
    ReasonExitCode0                         = 'Erfolgreich beendet'
    ReasonExitCode3010                      = 'Erfolgreich, ein Neustart ist nötig'
    ReasonExitCode1641                      = 'Erfolgreich, das Installationsprogramm hat einen Neustart eingeleitet'
    ReasonExitCode1602                      = 'Vom Benutzer abgebrochen'
    ReasonExitCode1223                      = 'Vom Benutzer abgebrochen'
    ReasonExitCode1605                      = 'Das Produkt ist nicht installiert'
    ReasonExitCode1614                      = 'Das Produkt ist bereits deinstalliert'
    ReasonExitCode1603                      = 'Schwerer Fehler im Installationsprogramm (MSI 1603)'
    ReasonExitCode1618                      = 'Eine andere Installation läuft gerade; später erneut versuchen'
    ReasonExitCode1619                      = 'Installationspaket konnte nicht geöffnet werden'
    ReasonExitCode1638                      = 'Eine andere Version des Produkts ist bereits installiert'
    ReasonExitCode740                       = 'Das Programm verlangt Administratorrechte'
    ReasonExitCode0x8A15002B                = 'winget: kein passendes Update gefunden'
    ReasonExitCode0x8A15004F                = 'winget: die verfügbare Version ist nicht neuer als die installierte'
    ReasonExitCode0x8A150014                = 'winget: Paket nicht gefunden'
    ReasonExitCode0x8A150017                = 'winget: kein Manifest für diese ID gefunden'
    ReasonExitCode0x8A150010                = 'winget: kein Installationsprogramm passt zu diesem System'
    ReasonExitCode0x8A150011                = 'winget: Prüfsumme des Installationsprogramms stimmt nicht (abgebrochen)'
    ReasonExitCode0x8A15002D                = 'winget: Installationsprogramm hat die Sicherheitsprüfung nicht bestanden'
    ReasonExitCode0x8A150008                = 'winget: Download fehlgeschlagen'
    ReasonExitCode0x8A150019                = 'winget: Befehl verlangt Administratorrechte'
    ReasonExitCode0x8A150056                = 'winget: das Installationsprogramm darf nicht mit Administratorrechten laufen'
    ReasonExitCode0x8A15007D                = 'winget: Pakete im Benutzerbereich dürfen nicht aus einem Administratorkontext geändert werden'
    ReasonExitCode0x8A15002F                = 'winget: kein Deinstallationsbefehl gefunden'
    ReasonExitCode0x8A150030                = 'winget: Deinstallationsbefehl ist fehlgeschlagen'
    ReasonExitCode0x8A150041                = 'winget: Paketvereinbarung nicht akzeptiert'
    ReasonExitCode0x8A150046                = 'winget: Quellvereinbarung nicht akzeptiert'
    ReasonExitCode0x8A15003A                = 'winget: durch Gruppenrichtlinie blockiert'
    ReasonExitCode0x8A15001B                = 'winget: Microsoft Store durch Richtlinie blockiert'
    ReasonExitCode0x8A15001C                = 'winget: Store-App durch Richtlinie blockiert'
    ReasonExitCode0x8A150068                = 'winget: das Paket ist angeheftet (pin) und wird nicht aktualisiert'
    ReasonExitCode0x8A15008E                = 'winget: das Update nutzt eine andere Installationstechnik als die installierte Version'
    ReasonExitCode0x8A15006D                = 'winget: ein benötigter Dienst ist ausgelastet; später erneut versuchen'
    ReasonExitCode0x8A150005                = 'winget: abgebrochen'
    ReasonExitCode0x8A150101                = 'Das Programm läuft noch; bitte beenden und erneut versuchen'
    ReasonExitCode0x8A150111                = 'Das Programm wird von einer anderen Anwendung benutzt'
    ReasonExitCode0x8A150102                = 'Eine andere Installation läuft gerade; später erneut versuchen'
    ReasonExitCode0x8A150103                = 'Dateien sind in Benutzung; Programm beenden und erneut versuchen'
    ReasonExitCode0x8A150104                = 'Eine Abhängigkeit fehlt'
    ReasonExitCode0x8A150105                = 'Nicht genug Speicherplatz'
    ReasonExitCode0x8A150106                = 'Nicht genug Arbeitsspeicher'
    ReasonExitCode0x8A150107                = 'Keine Netzwerkverbindung'
    ReasonExitCode0x8A150108                = 'Fehler im Installationsprogramm; Hersteller kontaktieren'
    ReasonExitCode0x8A150109                = 'Neustart nötig, um abzuschließen'
    ReasonExitCode0x8A15010A                = 'Erst neu starten, dann erneut versuchen'
    ReasonExitCode0x8A15010B                = 'Der PC wird neu gestartet, um abzuschließen'
    ReasonExitCode0x8A15010C                = 'Vom Benutzer abgebrochen'
    ReasonExitCode0x8A15010D                = 'Eine andere Version ist bereits installiert'
    ReasonExitCode0x8A15010E                = 'Eine höhere Version ist bereits installiert'
    ReasonExitCode0x8A15010F                = 'Durch Richtlinien der Organisation blockiert'
    ReasonExitCode0x8A150110                = 'Abhängigkeiten konnten nicht installiert werden'
    ReasonExitCode0x8A150113                = 'Paket wird von diesem System nicht unterstützt'
    ReasonExitCode0x8A150114                = 'Das Installationsprogramm kann die vorhandene Version nicht aktualisieren'
    ReasonExitCode0x8A150115                = 'Installationsprogramm meldet einen eigenen Fehler'
    ReasonExitCodeUnknown                   = 'Unbekannter Exit-Code {0}'

    # Fehler (Get-LocalizedString)
    ErrorNotInventoryRecord                 = 'Eingabe ist kein Inventar-Datensatz (SoftwareRecord, SecurityRating oder UpdateStatus).'

    # Einstellungen (Schlüssel = SettingsError + Code)
    SettingsErrorInvalidAdvisorEndpoint     = 'Ungültige Adresse ''{0}'': erwartet wird http:// oder https:// ohne Benutzerdaten, z. B. http://localhost:11434/v1.'
}
