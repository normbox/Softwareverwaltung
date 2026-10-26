# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Das Projekt ist noch nicht veröffentlicht; die Einträge sind nach Etappen gegliedert.

## Unveröffentlicht

### Nachbesserung: Suche nach portablen Programmen

#### Behoben

- Die App suchte keine portablen Programme, obwohl Nutzungsspuren, Ordner und Laufwerke einstellbar waren. Neu: `Invoke-InventoryScan` liest die installierten Programme und sucht portable Programme nur, wenn Spuren, Ordner oder Laufwerke eingerichtet sind (ohne Warnung, wenn nicht; installierte Programme werden nicht doppelt gelesen). Die App scannt damit; portable Programme erscheinen mit Quelle „Portable“, die Details zeigen den Fundort.

#### Geändert

- Einstellungen: Abschnitt „Suche nach portablen Programmen“ neu aufgebaut. Hauptschalter „Nach portablen Programmen suchen“ (`Set-InventorySetting -PortableSearch`, standardmäßig aus, keine Vorlage schaltet ihn ein); erst wenn er an ist, ist der Rest aktiv, vorher ausgegraut. Direkt darunter als neutrale Info der Hinweis, dass installierte Programme unabhängig davon erfasst werden. Dann „Wo suchen“ als Entweder-oder (`FileScan.Mode`, `Set-InventorySetting -ScanMode Drives|Folders|None`), keine Option vorausgewählt: „Ganze Laufwerke“ (alle erkannten Laufwerke einzeln, auch Wechseldatenträger wie USB; mit Hinweis auf lange Dauer, sobald eines angehakt ist) oder „Nur bestimmte Ordner“ (Liste mit „Entfernen“ je Eintrag, „Ordner auswählen…“, Vorschläge `%USERPROFILE%` und Downloads; standardmäßig leer). Angezeigt und durchsucht wird nur die gewählte Option; die Auswahl der anderen bleibt gespeichert. Dann „Wie suchen“: Nutzungsspuren, Temp, Prüfsumme, Ausschlüsse. Wer vorher Spuren oder Ordner eingerichtet hatte, muss die Suche einmal einschalten; gespeicherte Ordner werden als „Nur bestimmte Ordner“ übernommen, sonst gespeicherte Laufwerke als „Ganze Laufwerke“.
- Ohne gewählte Option oder mit leerer Liste der gewählten Option läuft kein Dateiscan; Nutzungsspuren wirken unabhängig davon. Die Einstellungsseite zeigt das als Hinweis, der Scan meldet es ebenfalls (Text in den Modultexten). Auch `Get-PortableSoftware` ohne Parameter nutzt nur die aktive Option.
- Vorlagen setzen nur sichtbare Schalter, die Option „Wo suchen“ und nur deren Einträge, nie den Hauptschalter; die Statuszeile nennt jede Änderung (z. B. „Wo suchen: Nur bestimmte Ordner; Ordner: %USERPROFILE%“).
- App-Texte: Grundlage für `.resx` (`Resources/Strings.resx`, `{loc:Text Schlüssel}` in XAML, `AppText.Get` in C#) mit Test, dass jeder verwendete Schlüssel existiert. Die neuen Texte stehen schon dort.

### Etappe 4a: KI-Berater im Modul

#### Hinzugefügt

- Tools für den KI-Berater: `get_inventory`, `get_program_details`, `check_latest_version`, `search_vulnerabilities`, `propose_update`, `propose_uninstall`. `Get-AdvisorTool` beschreibt sie anbieterunabhängig (JSON-Schema) und liefert mit `-SystemPrompt` die Systemanweisung; `Invoke-AdvisorTool` prüft die Argumente und gibt bereinigtes JSON zurück, Fehler als Meldung für das Modell. Vorschläge führen nie etwas aus.
- `Set-AdvisorContext`: übergibt die Bewertungen des letzten Scans, damit nicht jede Frage einen Scan auslöst.
- `Protect-PrivateText`: gemeinsame Bereinigung für Berater und HTML-Bericht – eigenes Profil (auch in JSON und mit `/`), Profile anderer Benutzer, Benutzername, Rechnername, Domäne, API-Schlüssel.
- Einstellungen `Advisor` (Schalter, Vorgabe, Adresse, Modell; standardmäßig aus, kein Standardmodell) und `Get-AdvisorEndpointPreset` mit den Standardadressen von Ollama, LM Studio und Unsloth Studio sowie „Eigene Adresse“. Schlüssel für den KI-Server über `Set-ServiceCredential -Service Advisor`.
- Doku `docs/BERATER.md`.
- Mehrsprachigkeit vorbereitet: neue Texte des Moduls in `SoftwareInventory.Strings.psd1` (geladen mit `Import-LocalizedData`, abgerufen mit `Get-LocalizedString`, Basissprache Deutsch). Fehler und Status des Beraters als feste Codes (`error_code`, `status_code`). Der Platzhalter für fremde Benutzerprofile ist sprachneutral `%OTHERUSER%`. Ein Test prüft, dass jeder verwendete Text-Schlüssel existiert. Regel in CLAUDE.md; bestehende Texte folgen in einer eigenen Etappe.

#### Geändert

- Entscheidung: Etappe 4 nur mit lokalen Modellen über die OpenAI-kompatible Schnittstelle; externe Anbieter (z. B. Claude API) später als Plugin. CLAUDE.md, KONZEPT.md und README angepasst.

### Etappe 3c: Details und Aktions-Buttons

#### Hinzugefügt

- App: In der Detailansicht einer Zeile die Buttons „Aktualisieren“ (nur bei verfügbarem Update) und „Deinstallieren“. Vorher fragt die App das Modul mit `-WhatIf` und zeigt einen Bestätigungsdialog mit dem genauen Befehl, ob Administratorrechte nötig sind und ob ein Wiederherstellungspunkt angelegt wird. „Abbrechen“ ist Standard.
- Ausgeführt wird nur der bestätigte Befehl: neuer Parameter `-ConfirmedCommandLine` für `Update-Software` und `Uninstall-Software`. Weicht der neu ermittelte Befehl ab, wird nichts ausgeführt (`Cancelled`, protokolliert).
- Ergebnis-Karte nach jeder Aktion: Ergebnis im Klartext, Meldung, Wiederherstellungspunkt; bei Fehlschlag „Mit <Methode> versuchen“ (wieder mit eigener Bestätigung), bei `ManualUpdateRequired` der Herstellerlink.
- Nach einer Aktion wird nur dieses Programm neu geprüft (`Find-InstalledSoftware`, findet es auch nach einem MSI-Update mit neuem Registry-Schlüssel über die winget-ID); deinstallierte Programme verschwinden aus der Liste.
- Detailansicht: Installationsart und -bereich, winget-ID, Ort und die bisherigen Aktionen zu diesem Programm aus dem Aktionsprotokoll.
- `Install-WingetPackageManager`: installiert winget (App Installer) über `Repair-WinGetPackageManager -Latest` nur für das eigene Konto, mit Bestätigung und Protokoll (`Get-ActionLog -Action InstallWinget`). In der App als Button „winget installieren“ in der Hinweis-Karte, wenn winget fehlt.
- Während einer Aktion sind Scan und weitere Aktionen gesperrt; die Statuszeile sagt, wenn Windows nach Administratorrechten fragt.

### Etappe 3d: Nachtrag Ampel

#### Geändert

- KEV-Treffer werden widerlegt, wenn die NVD für die installierte Version keinen Befall meldet oder der Katalog eine Angabe „behoben ab“ (`KevFixed`) hat und die Version gleich oder neuer ist. Widerlegte Treffer stehen in `Refuted` und als Grund in der Ampel; sie färben nie. Ohne NVD bleibt die Ampel dann Grau (nicht vollständig geprüft), mit NVD Grün. 7-Zip: CVE-2025-0411 behoben ab 24.09.
- Ist die installierte Version älter als „behoben ab“, gilt sie ohne NVD als sicher betroffen (bei KEV Rot).
- App: Spalte „Lücken“ zählt auch „möglicherweise betroffen“ (z. B. „1 möglich“, „2 + 1 möglich“), auch wenn nicht vollständig geprüft wurde. Neue Spalte „Grund“ zeigt den ersten Grund direkt in der Liste. Ein Klick auf eine Zeile zeigt alle Gründe, die Lücken mit CVE-Link, Bewertung, KEV, CVSS, EPSS und Beschreibung sowie widerlegte Treffer.

### Etappe 3d: Einstellungen

#### Hinzugefügt

- `Set-ServiceCredential`, `Remove-ServiceCredential`, `Get-ServiceCredentialStatus`: NVD-Schlüssel und GitHub-Token in der Windows-Anmeldeinformationsverwaltung (nur aktueller Benutzer, ohne Zusatzpaket). Ein gespeicherter Schlüssel hat Vorrang vor `NVD_API_KEY`/`GITHUB_TOKEN`; der Status nennt nur „vorhanden“ und die Quelle, nie den Schlüssel. Maskiert werden Schlüssel aus beiden Ablagen.
- `Get-SettingPreset`: liefert die Werte der Vorlagen „Quick“ und „Thorough“, ohne zu speichern. `Set-InventorySetting -Preset` nutzt dieselbe Funktion.
- App: Reiter „Programme“ und „Einstellungen“. Die Einstellungsseite zeigt alle Quellen, Nutzungsspuren, den Dateiscan (Ordner, Laufwerke, Temp, Hash, Ausschlüsse), externe Dienste mit Angabe, was gesendet wird, API-Schlüssel, Wiederherstellungspunkt und die Grenzen für Logs. Änderungen gelten erst nach „Speichern“, „Verwerfen“ stellt den gespeicherten Stand wieder her. Die Vorlagen belegen nur vor.
- Beim ersten Start fragt die App „Privat“ oder „Firma“ ab und zeigt danach die passenden Hinweise zu den Nutzungsbedingungen der externen Dienste. Es wird nichts eingeschaltet; alles bleibt aus und wird von Hand eingestellt. Die Hinweise stehen auch auf der Einstellungsseite.
- `Get-ServiceTermsNotice`: Kurzfassung der Nutzungsbedingungen von winget-Quellen, GitHub, NVD, CISA KEV und FIRST EPSS mit Link zum Original, bei „Firma“ mit Zusatzhinweisen. Ändert keine Einstellung.
- xUnit-Tests für die Einstellungsseite und für den Einstellungs-Service mit dem echten Modul (umgelenkte Einstellungsdatei, eigener Präfix in der Anmeldeinformationsverwaltung).

### Etappe 3b: WPF-Grundgerüst

#### Hinzugefügt

- WPF-App (.NET 10, Fluent-Design mit WPF-UI), folgt Hell/Dunkel und Akzentfarbe von Windows.
- Eingebettete PowerShell-Engine (`Microsoft.PowerShell.SDK` 7.6.9). Kern-Modul und das mitgelieferte `Microsoft.WinGet.Client` 1.29.380 werden mit vollem Pfad geladen; Ausführungsrichtlinie „Bypass“ nur für die eigene Sitzung. Aufrufe laufen im Hintergrund und sind abbrechbar.
- Hauptliste aus `Get-SoftwareInventory | Get-SecurityRating`: Ampel mit Text und Gründen, Name, Hersteller, installierte und neueste Version (mit „unbestätigt“), Zahl der Lücken (leer, wenn nicht geprüft), Quelle. Suche, Filter „Nur Updates verfügbar“ und „Nur Sicherheitsrisiken“.
- Hinweise oben im Fenster für Warnungen und Fehler des Moduls sowie für fehlendes winget, mit Link zu App Installer im Microsoft Store.
- `Test-WingetAvailability`: prüft winget.exe und das Modul `Microsoft.WinGet.Client` und beschreibt, was fehlt.
- Begleitpakete: Store-Pakete mit `AllowExternalContent` (Kontextmenü von WinMerge, Edge, OneDrive …) werden dem Programm unter `Companions` zugeordnet, wenn das eindeutig ist; sonst bleiben sie mit Flag `SparsePackage` stehen. Snapshot-Schema 3.
- `build/Publish-App.ps1`: self-contained für Windows x64, als Ordner und ZIP.
- `tests/Sandbox/Start-AppSandbox.ps1`: startet die veröffentlichte App in Windows Sandbox ohne .NET, PowerShell 7 und winget.
- `THIRD-PARTY-NOTICES.md` mit allen mitgelieferten Komponenten.
- xUnit-Tests für die eingebettete Engine, die Abbildung der Moduldaten und das ViewModel.

### Etappe 3a: Aktionen im Modul

#### Hinzugefügt

- `Update-Software`: aktualisiert über winget (`upgrade --id … --exact --source …`). Ohne winget-Paket wird nichts heruntergeladen, das Ergebnis enthält nur den Herstellerlink.
- `Uninstall-Software`: deinstalliert über winget, MSI (`msiexec /x {ProductCode} /qn /norestart /l*v`), Store-App, `QuietUninstallString` oder `UninstallString`. Wählbar mit `-Method`.
- `-WhatIf` liefert `Result = Planned` mit dem genauen Befehl, für den Bestätigungsdialog der App. `Uninstall-Software` fragt standardmäßig nach (ConfirmImpact High).
- Rückgabe als `SoftwareInventory.ActionResult` mit einheitlichem `Result`, Exit-Code, Zustand vorher und nachher, Wiederherstellungspunkt und nächster Methode.
- Erfolg wird geprüft: Der Eintrag muss weg bzw. die Version höher sein, sonst lautet das Ergebnis `NotVerified`.
- Adminrechte nur pro Aktion und nur für Programme des ganzen Rechners. Für Einträge unter HKCU und für Store-Apps gibt es nie Adminrechte. Bei unbekanntem Bereich fordert winget die UAC selbst an.
- Erhöhter Helfer für Windows PowerShell 5.1. Der Plan wird als Argument übergeben, das Skript per SHA256 geprüft. Das Ergebnis kommt über eine Named Pipe zurück, die nur erhöhte Clients öffnen dürfen; geprüft werden auch PID und Nonce.
- Befehle aus der Registry werden ohne Shell ausgeführt. Interpreter werden abgelehnt. Mit Adminrechten wird keine Datei gestartet, die der Benutzer verändern könnte.
- Optionaler Wiederherstellungspunkt (Einstellung `RestorePoint`, standardmäßig aus, oder `-CreateRestorePoint`). Er meldet `Created`, `Skipped`, `NotAvailable` oder `Failed` und bricht die Aktion nie ab.
- `Get-ActionLog`: Aktionsprotokoll als JSON-Zeilen unter `%LOCALAPPDATA%\SoftwareInventory\logs\actions`, mit Filtern. Beschädigte Zeilen werden übersprungen.
- Selbstbereinigung beim Laden des Moduls: Logs und Cache werden auf höchstens 30 Tage und 100 MB begrenzt, einstellbar mit `Set-InventorySetting -LogRetentionDays/-LogMaxSizeMB`. MSI-Logs werden nur bei Fehlern komprimiert aufgehoben.
- Integrationstest für Windows Sandbox (`tests/Sandbox`) mit festen Versionen und Prüfung von Hash und Signatur.

#### Behoben (gefunden im Sandbox-Test)

- MSI-Updates mit neuem ProductCode meldeten `NotVerified`, obwohl das Update geklappt hatte. Ist der alte Registry-Eintrag weg, zählt jetzt die Version laut winget.
- Läuft die App bereits mit Adminrechten (z. B. bei abgeschalteter UAC), galt jedes Programm unter „Programme“ als für Benutzer beschreibbar und wurde abgelehnt. Schreibrechte von Administratoren, SYSTEM und TrustedInstaller zählen nicht mehr.
- Programme des Benutzers (HKCU) liegen meist unter `AppData`. Der Helfer lehnt Benutzerordner jetzt nur noch ab, wenn er erhöht startet.
- Die Zustandsabfrage über winget nennt die Quelle. Vorher scheiterte sie ganz, sobald die Store-Quelle gestört war.

### Etappe 2c: Ampel und Bericht

- `Get-SecurityRating` (Rot, Gelb, Grün, Grau mit Grund) und `Export-SecurityReport` (HTML).

### Etappe 2b: Schwachstellen

- `Get-SoftwareVulnerability` mit NVD, CISA KEV und EPSS; CPE-Zuordnung über den Katalog (`Find-CpeCandidate`, `Set-CpeMapping`).

### Etappe 2a: Versionen

- `Test-SoftwareUpdate` und `Compare-SoftwareVersion`; neueste Version über winget, GitHub-Releases und winget-Suche; Produktkatalog.

### Etappe 1 und 1b: Inventar

- `Get-SoftwareInventory` (Registry, winget, Store-Apps), Snapshots (`Save-`, `Get-`, `Compare-InventorySnapshot`), `Get-PortableSoftware`, Einstellungen (`Get-`/`Set-InventorySetting`, alles standardmäßig aus).
