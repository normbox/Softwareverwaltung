# KI-Berater

Der Berater beantwortet Fragen zu den installierten Programmen, zur Ampel und zu Sicherheitslücken. Er arbeitet mit einem **lokalen** Sprachmodell. Daten holt er sich über Tools aus dem Modul, und er führt nie selbst etwas aus.

```powershell
Set-InventorySetting -AdvisorPreset Ollama -AdvisorModel 'qwen3:8b' -AdvisorEnabled $true   # Modellname wie unter /v1/models
Get-AdvisorTool | Format-Table Name, Kind                                                  # Tools und ihre Art
(Invoke-AdvisorTool -Name get_inventory -ArgumentsJson '{"rating":"Red"}').Content         # bereinigtes JSON für das Modell
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

Stand der Adressen: 26.10.2026. Maßgeblich ist die Dokumentation des jeweiligen Programms.

## Tools

| Tool | Art | Wirkung |
| --- | --- | --- |
| `get_inventory` | Read | Programme aus dem letzten Scan mit Ampel, Versionen und Zahl der Lücken. Filter: `filter` (Name/Hersteller), `rating`, `updates_only`, `limit` (1–200, Standard 50). Liefert je Programm eine `id`. |
| `get_program_details` | Read | Alle Gründe der Ampel, Lücken (CVE, KEV, CVSS, EPSS, höchstens 25), widerlegte Treffer, Installationsart, winget-ID |
| `check_latest_version` | Read | Prüft die neueste Version neu (nur aktivierte Dienste) |
| `search_vulnerabilities` | Read | Sucht Lücken neu (nur aktivierte Dienste) |
| `propose_update` | Proposal | Schlägt ein Update vor; nur bei bekanntem Update |
| `propose_uninstall` | Proposal | Schlägt eine Deinstallation vor |

- Die `id` (`p-` plus 12 Hex-Zeichen) ist ein Hash des stabilen Schlüssels eines Programms. Sie enthält keine Pfade und keine Namen.
- Die Tools arbeiten mit den Daten des letzten Scans. Die App übergibt sie mit `Set-AdvisorContext`. Ohne diesen Aufruf liest das Modul beim ersten Tool-Aufruf einmal selbst ein.
- Fehler kommen als `Ok = $false` mit festem Code (`Code`, im JSON `error_code`) und einer Meldung in der Sprache der Oberfläche zurück, damit das Modell sich korrigieren kann. Codes: `UnknownTool`, `InvalidArguments`, `InvalidId`, `UnknownId`, `InvalidLimit`, `InvalidRating`, `ReasonMissing`, `NoUpdateKnown`, `ToolFailed`; Vorschläge melden `ProposalCreated`.
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
