# KI-Berater

Der Berater beantwortet Fragen zu den installierten Programmen, zur Ampel und zu Sicherheitslücken. Er arbeitet mit einem **lokalen** Sprachmodell. Daten holt er sich über Tools aus dem Modul, und er führt nie selbst etwas aus.

```powershell
Set-InventorySetting -AdvisorPreset Ollama -AdvisorModel 'qwen3:8b' -AdvisorEnabled $true   # Modellname wie unter /v1/models
Get-AdvisorTool | Format-Table Name, Kind                                                  # Tools und ihre Art
(Invoke-AdvisorTool -Name get_inventory -ArgumentsJson '{"rating":"Red"}').Content         # bereinigtes JSON für das Modell
Set-InventorySetting -AdvisorShareLevelLocal 2                                             # Freigabestufe für lokale Server
(Get-AdvisorDataPreview -Level 1).Details                                                  # was das Modell auf Stufe 1 sähe
Get-AdvisorEndpointCheck -Endpoint 'http://192.168.1.20:11434/v1'                          # ist die Adresse lokal?
```

## Server

Unterstützt werden lokale Server mit OpenAI-kompatibler Schnittstelle (`/v1/chat/completions` mit `tools`). Das Modell muss Tool-Aufrufe beherrschen.

| Vorgabe | Standardadresse | API-Schlüssel |
| --- | --- | --- |
| `Ollama` | `http://localhost:11434/v1` | nein |
| `LMStudio` | `http://localhost:1234/v1` | nein (lokalen Server in LM Studio starten) |
| `Unsloth` | `http://localhost:8888/v1` (Port nicht fest, oft 8888, manchmal 8000) | ja, `sk-unsloth-…` |
| `Custom` | eigene Adresse | optional |

- Es gibt **kein Standardmodell**. Gewählt wird aus den Modellen, die der Server unter `/v1/models` meldet.
- Den Schlüssel speichert `Set-ServiceCredential -Service Advisor` in der Windows-Anmeldeinformationsverwaltung. Alternativ dient die Umgebungsvariable `SOFTWAREINVENTORY_ADVISOR_KEY`.
- AnythingLLM fehlt vorerst: Seine OpenAI-Schnittstelle gibt `tools` nicht weiter, und „model“ ist dort ein Arbeitsbereich.
- Externe Anbieter (z. B. Claude API) kommen später als Plugin über die Anbieter-Schnittstelle der App (siehe unten).
- **Nur lokale Adressen:** `Get-AdvisorEndpointCheck` löst den Namen auf und prüft jede IP-Adresse, nicht nur den Namen. Erlaubt sind Loopback und private Netze: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, Link-Local 169.254.0.0/16, IPv6 fc00::/7 und fe80::/10. Öffentliche Adressen (auch 100.64.0.0/10) lehnt `Set-InventorySetting -AdvisorEndpoint` mit dem Code `AdvisorEndpointNotLocal` ab, nicht auflösbare Namen mit `AdvisorEndpointUnresolvable`. http im privaten Netz ist erlaubt, mit dem Hinweis `AdvisorEndpointUnencrypted`. Beim Verbinden prüft die App zusätzlich jede Adresse selbst und verbindet nur zu geprüften (siehe unten).

Stand der Adressen: 26.10.2026. Maßgeblich ist die Dokumentation des jeweiligen Programms.

## Freigabestufen

Wie viel das Modell sieht, legt die Freigabestufe fest (Tabelle in [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md#was-die-ki-sehen-darf-freigabestufen)). Die Grenze setzen die Tools selbst, nicht der Prompt: Was eine Stufe nicht zeigt, steht nicht im Ergebnis.

- **Je Anbieterart eine Stufe** in `Advisor.ShareLevel`: `Local` (Voreinstellung 3, höchstens 4) und `External` für spätere Plugins (Voreinstellung 1, höchstens 3; Stufe 4 nie extern). Gesetzt mit `Set-InventorySetting -AdvisorShareLevelLocal` bzw. `-AdvisorShareLevelExternal`.
- `Invoke-AdvisorTool -ProviderKind Local|External` (Voreinstellung `Local`) bestimmt die Stufe selbst aus Einstellung und Höchststufe (`Get-AdvisorShareLimit`); der Aufrufer kann sie nicht erhöhen. Eine Richtlinie für Firmen, die die Höchststufe senkt, kommt mit Etappe 6.
- **Ältere Einstellungen** ohne Stufe bekommen lokal Stufe 2 und `ShareLevelNoticePending`; die App weist einmal darauf hin (in den Einstellungen immer, im Hauptfenster nur bei eingeschaltetem Berater), bis der Benutzer „Verstanden“ klickt oder eine Stufe speichert. Höher stellt nur der Benutzer; neue Einstellungen beginnen mit Stufe 3.
- **Stufe 0:** Es gibt nur `get_inventory`, ohne Parameter (sonst ließen sich Namen über `filter` einzeln abfragen). Antwort: Anzahl Programme, Ampelverteilung, verfügbare Updates, Anzahl Lücken, KEV-Lücken und CVE-Nummern ohne Programmzuordnung (höchstens 200). Die anderen Tools melden `ShareLevelTooLow`, `Get-AdvisorTool` beschreibt nur dieses eine.
- **Stufe 1:** Liste und Details mit Name, Hersteller, Versionen, Ampel, Gründen und Lücken; keine Installationsdetails, keine portablen Programme.
- **Stufe 2:** zusätzlich `sources`, `install_type`, `scope`, `architecture`, `winget_id`, `winget_source` und bei installierten Programmen `install_location` mit Platzhaltern (`%PROGRAMFILES%\7-Zip`, Benutzerpfade über die Bereinigung).
- **Stufe 3:** zusätzlich portable Programme, die die **Dateisuche** gefunden hat (`kind: portable`), mit `signature_status`, `signer`, `location_kind` (Downloads, Desktop, Documents, Temp, AppData, ProgramFiles, UserProfile, RemovableDrive, NetworkDrive, OtherDrive, Other) und `flags` (`unsigned`, `invalid_signature`, `in_downloads_or_temp`, `multiple_versions`). Der Pfad eines portablen Programms geht nie mit.
- **Stufe 4:** zusätzlich portable Programme, die nur über Nutzungsspuren gefunden wurden, sowie `last_used` (`within_1_month`, `1_to_6_months`, `older`, `unknown`) und `autostart`. Fehlende Spuren heißen `unknown`, nicht „nie genutzt“.
- **Anzahlen** beziehen sich auf die Programme, die die Stufe zeigt; auf Stufe 0 bis 2 zählen portable Programme nicht mit.
- **Nie an die KI:** Produktcode, Registry-Schlüssel, Deinstallationsbefehle, Symbolpfad, Begleitpakete, Paketnamen, Hash, weitere Fundorte, Installationsdatum, genaue Zeitstempel, Startzähler und die Art der Spur. Tests sichern das für jede Stufe ab.
- `Get-AdvisorDataPreview -Level n` zeigt genau, was das Modell bekäme (bereinigtes JSON von `get_inventory` mit 5 Programmen und `get_program_details` für das erste), ohne etwas zu senden. Die App nutzt das für die Vorschau in den Einstellungen.

## Tools

| Tool | Art | Wirkung |
| --- | --- | --- |
| `get_inventory` | Read | Programme aus dem letzten Scan mit Ampel, Versionen und Zahl der Lücken. Filter: `filter` (Name/Hersteller), `rating`, `updates_only`, `limit` (1–200, Standard 50). Liefert je Programm eine `id`. |
| `get_program_details` | Read | Alle Gründe der Ampel, Lücken (CVE, KEV, CVSS, EPSS, höchstens 25), widerlegte Treffer, Lücken nur für andere Plattformen; ab Stufe 2 Installationsdetails |
| `check_latest_version` | Read | Prüft die neueste Version neu (nur aktivierte Dienste) |
| `search_vulnerabilities` | Read | Sucht Lücken neu (nur aktivierte Dienste) |
| `propose_update` | Proposal | Schlägt ein Update vor; nur bei bekanntem Update |
| `propose_uninstall` | Proposal | Schlägt eine Deinstallation vor |

- Die `id` (`p-` plus 12 Hex-Zeichen) ist ein Hash des stabilen Schlüssels eines Programms. Sie enthält keine Pfade und keine Namen.
- Die Tools arbeiten mit den Daten des letzten Scans. Die App übergibt sie nach jedem Scan mit `Set-AdvisorContext`. Das Modul liest **nie selbst ein**, weil ein Scan externe Dienste abfragt und nur auf Wunsch des Benutzers startet: Ohne Daten aus einem Scan antwortet jedes Tool mit `NoScanData`, und die Vorschau meldet `HasScanData = $false`. Ein Scan ohne Programme zählt als Scan.
- Fehler kommen als `Ok = $false` mit festem Code (`Code`, im JSON `error_code`) und einer Meldung in der Sprache der Oberfläche zurück, damit das Modell sich korrigieren kann. Codes: `UnknownTool`, `InvalidArguments`, `InvalidId`, `UnknownId`, `InvalidLimit`, `InvalidRating`, `ReasonMissing`, `NoUpdateKnown`, `ShareLevelTooLow`, `NoScanData`, `ToolFailed`; Vorschläge melden `ProposalCreated`.
- Vorschläge führen nichts aus. `Proposal` enthält Aktion, Programm, Begründung und die Bewertung für die Oberfläche. Das Modell bekommt nur die Vorschlags-ID und den Hinweis, dass der Benutzer selbst entscheidet. Bestätigt und ausgeführt wird wie bei den Buttons, also mit Bestätigungsdialog und genau dem bestätigten Befehl (siehe [AKTIONEN.md](AKTIONEN.md)).
- `Get-AdvisorTool -SystemPrompt` liefert die Systemanweisung: auf Deutsch antworten, nur auf Tool-Ergebnisse stützen, nur vorschlagen, „möglicherweise betroffen“ nicht als sicher darstellen.
- Gründe, Hinweise und widerlegte Treffer bekommt das Modell als `code`, `args` und `text`. So hängt auch dort die Logik am Code, und der Text ist in der Sprache der Oberfläche.
- Alle Texte (Tool-Beschreibungen, Systemanweisung, Meldungen, Hinweise zu den Vorgaben) stehen in `src/SoftwareInventory/SoftwareInventory.Strings.psd1` und kommen über `Import-LocalizedData` in der Sprache der Oberfläche; vorerst gibt es nur Deutsch.

## Anbieter-Schnittstelle der App

Die Gesprächsschleife liegt in der App (`src/Softwareverwaltung.App/Advisor`), die Daten und Regeln im Modul.

- **`IAdvisorProvider`**: `Kind` (Local oder External), `ListModelsAsync`, `CompleteAsync(Nachrichten, Tools)`. Nachrichten und Tools sind eigene Typen der App, nicht das Format eines Servers; ein späteres Plugin (z. B. Claude API) wandelt sie selbst um. Die Anbieterart geht an das Modul (`-ProviderKind`), das daraus die Freigabestufe bestimmt; ein Anbieter kann sie nicht erhöhen.
- **`OpenAiCompatibleProvider`** für lokale Server: `GET /models` und `POST /chat/completions` mit `tools` (`tool_choice: auto`), ohne Streaming. Argumente nimmt er als Text oder als Objekt an. Höchstens 8 MB je Antwort, Zeitgrenze 5 Minuten. Adresse, Modell und Schlüssel kommen aus `Get-AdvisorConnection`; der Schlüssel bleibt ein `SecureString` bis zum Header `Authorization: Bearer` und steht nie in Meldungen.
- **Prüfung beim Verbinden:** Die App löst den Namen selbst auf, lehnt ab, sobald eine Adresse öffentlich ist (`AdvisorEndpointNotLocal`) oder der Name nicht auflösbar (`AdvisorEndpointUnresolvable`), verbindet nur zu den geprüften Adressen und prüft danach die tatsächlich verbundene Gegenstelle. Ein Name, der zwischen Prüfung und Verbindung auf eine andere Adresse zeigt, hilft also nicht. TLS prüft weiter das Zertifikat gegen den Hostnamen der Adresse. Kein System-Proxy, keine Weiterleitungen (`AdvisorRedirectRefused`), keine Cookies; Verbindungen werden nach 2 Minuten neu aufgebaut und dabei erneut geprüft.
- Die Regel für lokale Adressen gibt es zweimal, im Modul (`Get-IpAddressNetwork`) und in der App (`LocalAddressPolicy`), damit die Prüfung beim Verbinden nicht an einem laufenden Scan hängt. Beide prüfen Pester und xUnit gegen dieselbe Tabelle `tests/Data/advisor-address-cases.json`.
- **`AdvisorConversation`**: Systemanweisung und Tools aus `Get-AdvisorTool -ProviderKind …`; die Frage des Benutzers läuft vor dem Senden durch `Protect-AdvisorText`. Tool-Aufrufe führt `Invoke-AdvisorTool -ProviderKind …` aus, bis das Modell antwortet, höchstens 8 Runden (`AdvisorToolRoundLimit`). Bei einem Fehler oder Abbruch bleibt das Gespräch wie vor der Frage. Ab 20 Fragen fallen die ältesten Runden samt ihren Tool-Aufrufen weg. Vorschläge werden gesammelt (Karten in Etappe 4c-2), ausgeführt wird nichts.
- Läuft gerade ein Scan, warten Tool-Aufrufe an der Sperre der eingebetteten PowerShell. Dienste werden also nie parallel zu einem Scan abgefragt.
- Nach jedem Scan übergibt die App die Bewertungen mit `Set-AdvisorContext`.
- **Verbindung testen** (`AdvisorService.TestConnectionAsync`, Knopf auf der Einstellungsseite): Adresse prüfen (mit Hinweis „unverschlüsselt“), Modelle abrufen, gewähltes Modell vorhanden, dann eine Anfrage mit festen Testtexten und nur `get_inventory`. Der Tool-Aufruf wird nicht ausgeführt, es gehen keine Inventardaten an das Modell. Ruft das Modell kein Tool auf oder scheitert nur diese Anfrage, ist das eine Warnung; speichern geht trotzdem.
- Fehler der App haben feste Codes mit Texten in `Strings.resx`: `AdvisorEndpointInvalid`, `AdvisorEndpointNotLocal`, `AdvisorEndpointUnresolvable`, `AdvisorServerUnreachable`, `AdvisorTimeout`, `AdvisorRedirectRefused`, `AdvisorUnauthorized`, `AdvisorHttpError`, `AdvisorInvalidResponse`, `AdvisorResponseTooLarge`, `AdvisorNoModel`, `AdvisorDisabled`, `AdvisorToolRoundLimit`. Sie nennen höchstens den HTTP-Status, nie den Antworttext des Servers.

## Einstellungsseite

Abschnitt „KI-Berater“ in den Einstellungen der App:

- **Einschalten** (standardmäßig aus) geht nur mit Adresse und Modell; sonst lehnt `Set-InventorySetting` mit `AdvisorIncomplete` ab. Geprüft wird das nur, wenn sich Beraterwerte ändern.
- **Server** wählt eine Vorgabe und belegt die Adresse vor; bei „Eigene Adresse“ bleibt sie. Unter der Adresse steht der Hinweis „unverschlüsselt“, sobald ein Test oder „Modelle laden“ ihn meldet.
- **Modell:** Das Feld ist anfangs leer, es gibt kein Standardmodell. „Modelle laden“ füllt nur die Auswahlliste, das Feld bleibt frei editierbar.
- **API-Schlüssel** des KI-Servers wie die anderen Schlüssel (Anmeldeinformationsverwaltung); Hinweis, wenn die Vorgabe einen verlangt.
- **Verbindung testen** und **Modelle laden** nutzen die ungespeicherten Werte der Seite mit dem gespeicherten Schlüssel und laufen nur auf Klick.
- **Freigabestufe** als Auswahl 0 bis 4 mit je einem Satz, was dazukommt; bei Stufe 4 ein Hinweis zu den Nutzungsspuren. Die Stufe für externe Anbieter bleibt ausgeblendet, bis es das erste Plugin gibt.
- **Vorschau** (aufklappbar): `Get-AdvisorDataPreview` für die gerade gewählte Stufe, eingerückt; vor dem ersten Scan nur ein Hinweis.
- Gespeichert wird mit dem gemeinsamen „Speichern“. Beraterwerte gehen nur mit, wenn sie sich geändert haben; eine gespeicherte Adresse wird also nicht bei jedem Speichern neu aufgelöst, und eine unveränderte Stufe löscht den einmaligen Hinweis nicht.

## Chat-Seitenleiste

Der Knopf „KI-Berater“ rechts neben den Seitenreitern blendet die Seitenleiste ein und aus. Offen oder zu und die Breite (am linken Rand ziehbar) merkt sich die App in `app-ui.json`.

- **Leere Zustände:** Ist der Berater aus, steht dort ein Hinweis mit „Einstellungen öffnen“. Vor dem ersten Scan erscheint nur ein Hinweis, Fragen geht erst danach (das Modul liest nie selbst ein).
- **Fragen:** Eingabetaste sendet, Umschalt+Eingabetaste macht eine neue Zeile. „Abbrechen“ beendet die Antwort sofort; die Frage steht dann wieder im Eingabefeld, das Gespräch ist wie vorher. Fehler erscheinen mit ihrem Text in der Leiste, ebenfalls mit der Frage wieder im Eingabefeld.
- **Gleichzeitigkeit:** Solange ein Scan oder eine Aktion läuft, kann nicht gefragt werden. Solange der Berater antwortet, sind Scan und Aktionen gesperrt, weil seine Tools NVD und CIRCL abfragen können.
- **Antworten** erscheinen als reiner Text: Überschriften, Fett- und Codezeichen fallen weg, Aufzählungen werden zu „•“, Links zu „Text (Adresse)“ und sind nicht klickbar. Denkblöcke mancher Modelle (`<think>…</think>`) werden nicht angezeigt.
- Unter jeder Antwort steht, welche Daten das Modell abgefragt hat, z. B. „Abgefragt: Programmliste, Programmdetails (2×)“, oder „Ohne Datenabfrage beantwortet.“
- **Nur im Speicher:** Das Gespräch wird nie auf die Festplatte geschrieben, auch die Fragen nicht. Es verschwindet mit „Neues Gespräch“, beim Beenden und wenn sich gespeicherte Beraterwerte ändern (Ein/Aus, Vorgabe, Adresse, Modell, Freigabestufe); dann beginnt die Leiste mit einem Hinweis ein neues Gespräch.
- Vorschlagskarten folgen in Etappe 4c-2. Name, Versionen und Ampel auf einer Karte kommen dann immer aus der aktuellen Liste der App (über die Kennung des Programms), nie aus der Antwort des Modells; vom Modell stammen nur Aktion, Kennung und Begründung. Eine Karte führt nie selbst etwas aus.

## Bereinigung

Jede Tool-Antwort läuft durch `Protect-PrivateText`, **auch bei lokalen Modellen**:

| Was | Wird zu |
| --- | --- |
| eigenes Profil `C:\Users\<Name>`, auch als `C:\\Users\\…` in JSON und mit `/` | `%USERPROFILE%` |
| Profile anderer Benutzer | `C:\Users\%OTHERUSER%` (`Public` und `Default` bleiben) |
| Benutzername, Rechnername, Domäne (als ganzes Wort) | `%USERNAME%`, `%COMPUTERNAME%`, `%USERDOMAIN%` |
| gespeicherte API-Schlüssel | `***` |

Dieselbe Regel nutzt der HTML-Bericht.
