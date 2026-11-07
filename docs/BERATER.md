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
- Externe Anbieter (z. B. Claude API) kommen später als Plugin über die Anbieter-Schnittstelle der App.
- **Nur lokale Adressen:** `Get-AdvisorEndpointCheck` löst den Namen auf und prüft jede IP-Adresse, nicht nur den Namen. Erlaubt sind Loopback und private Netze: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, Link-Local 169.254.0.0/16, IPv6 fc00::/7 und fe80::/10. Öffentliche Adressen (auch 100.64.0.0/10) lehnt `Set-InventorySetting -AdvisorEndpoint` mit dem Code `AdvisorEndpointNotLocal` ab, nicht auflösbare Namen mit `AdvisorEndpointUnresolvable`. http im privaten Netz ist erlaubt, mit dem Hinweis `AdvisorEndpointUnencrypted`. Beim Verbinden prüft die App zusätzlich die tatsächlich verbundene Adresse (Etappe 4b-2).

Stand der Adressen: 26.10.2026. Maßgeblich ist die Dokumentation des jeweiligen Programms.

## Freigabestufen

Wie viel das Modell sieht, legt die Freigabestufe fest (Tabelle in [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md#was-die-ki-sehen-darf-freigabestufen)). Die Grenze setzen die Tools selbst, nicht der Prompt: Was eine Stufe nicht zeigt, steht nicht im Ergebnis.

- **Je Anbieterart eine Stufe** in `Advisor.ShareLevel`: `Local` (Voreinstellung 3, höchstens 4) und `External` für spätere Plugins (Voreinstellung 1, höchstens 3; Stufe 4 nie extern). Gesetzt mit `Set-InventorySetting -AdvisorShareLevelLocal` bzw. `-AdvisorShareLevelExternal`.
- `Invoke-AdvisorTool -ProviderKind Local|External` (Voreinstellung `Local`) bestimmt die Stufe selbst aus Einstellung und Höchststufe (`Get-AdvisorShareLimit`); der Aufrufer kann sie nicht erhöhen. Eine Richtlinie für Firmen, die die Höchststufe senkt, kommt mit Etappe 6.
- **Ältere Einstellungen** ohne Stufe bekommen lokal Stufe 2 und `ShareLevelNoticePending`; die App weist einmal darauf hin. Höher stellt nur der Benutzer.
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
- Die Tools arbeiten mit den Daten des letzten Scans. Die App übergibt sie mit `Set-AdvisorContext`. Ohne diesen Aufruf liest das Modul beim ersten Tool-Aufruf einmal selbst ein.
- Fehler kommen als `Ok = $false` mit festem Code (`Code`, im JSON `error_code`) und einer Meldung in der Sprache der Oberfläche zurück, damit das Modell sich korrigieren kann. Codes: `UnknownTool`, `InvalidArguments`, `InvalidId`, `UnknownId`, `InvalidLimit`, `InvalidRating`, `ReasonMissing`, `NoUpdateKnown`, `ShareLevelTooLow`, `ToolFailed`; Vorschläge melden `ProposalCreated`.
- Vorschläge führen nichts aus. `Proposal` enthält Aktion, Programm, Begründung und die Bewertung für die Oberfläche. Das Modell bekommt nur die Vorschlags-ID und den Hinweis, dass der Benutzer selbst entscheidet. Bestätigt und ausgeführt wird wie bei den Buttons, also mit Bestätigungsdialog und genau dem bestätigten Befehl (siehe [AKTIONEN.md](AKTIONEN.md)).
- `Get-AdvisorTool -SystemPrompt` liefert die Systemanweisung: auf Deutsch antworten, nur auf Tool-Ergebnisse stützen, nur vorschlagen, „möglicherweise betroffen“ nicht als sicher darstellen.
- Gründe, Hinweise und widerlegte Treffer bekommt das Modell als `code`, `args` und `text`. So hängt auch dort die Logik am Code, und der Text ist in der Sprache der Oberfläche.
- Alle Texte (Tool-Beschreibungen, Systemanweisung, Meldungen, Hinweise zu den Vorgaben) stehen in `src/SoftwareInventory/SoftwareInventory.Strings.psd1` und kommen über `Import-LocalizedData` in der Sprache der Oberfläche; vorerst gibt es nur Deutsch.

## Bereinigung

Jede Tool-Antwort läuft durch `Protect-PrivateText`, **auch bei lokalen Modellen**:

| Was | Wird zu |
| --- | --- |
| eigenes Profil `C:\Users\<Name>`, auch als `C:\\Users\\…` in JSON und mit `/` | `%USERPROFILE%` |
| Profile anderer Benutzer | `C:\Users\%OTHERUSER%` (`Public` und `Default` bleiben) |
| Benutzername, Rechnername, Domäne (als ganzes Wort) | `%USERNAME%`, `%COMPUTERNAME%`, `%USERDOMAIN%` |
| gespeicherte API-Schlüssel | `***` |

Dieselbe Regel nutzt der HTML-Bericht.
