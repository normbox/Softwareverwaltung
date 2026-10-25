# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Das Projekt ist noch nicht veröffentlicht; die Einträge sind nach Etappen gegliedert.

## Unveröffentlicht

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
