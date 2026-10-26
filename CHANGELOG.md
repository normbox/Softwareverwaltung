# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Das Projekt ist noch nicht veröffentlicht; die Einträge sind nach Etappen gegliedert.

## Unveröffentlicht

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
