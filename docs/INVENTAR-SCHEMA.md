# Inventar-Schema

Ein Snapshot ist eine JSON-Datei unter `%LOCALAPPDATA%\SoftwareInventory\scans\<yyyyMMdd-HHmmss-fff>.json` (Zeit in UTC).

```json
{
  "SchemaVersion": 3,
  "CreatedAt": "2026-10-24T13:36:00.708Z",
  "ModuleVersion": "0.1.0",
  "Records": [ { "Name": "7-Zip 26.05 (x64)", "...": "..." } ]
}
```

Snapshots mit einer höheren `SchemaVersion`, als das Modul kennt, werden beim Laden übersprungen. Bei älteren Snapshots werden fehlende Felder mit `null` ergänzt.

| Version | Änderung |
| --- | --- |
| 1 | Installierte Programme (Registry, winget, Store-Apps) |
| 2 | Portable Programme (`FilePath` bis `Flags`), `DisplayIcon` |
| 3 | `Companions` (zugeordnete Begleitpakete), Flag `SparsePackage` |

## Datensatz (`SoftwareInventory.SoftwareRecord`)

| Feld | Bedeutung | Quelle |
| --- | --- | --- |
| `Name` | Anzeigename; bei Store-Apps aus winget, bei portablen Programmen der Produktname der Datei | alle |
| `Publisher` | Hersteller | Registry, Appx, Portable |
| `Version` | Version, unverändert übernommen (Normalisierung folgt in Etappe 2) | alle |
| `InstallType` | `MSI`, `EXE`, `MSIX`, `Winget` (nur in winget bekannt) oder `Portable` | |
| `Scope` | `Machine` oder `User` | Registry, Appx, Portable |
| `Architecture` | `X64`, `X86`, `Arm64`, `Neutral` | Registry, Appx, Portable |
| `Sources` | Liste der Quellen: `Registry`, `Appx`, `Winget`, `Portable` | |
| `WingetId`, `WingetSource` | Paket-ID und Katalog (`winget`, `msstore`); nur bei Katalogpaketen | winget |
| `AvailableVersion` | Neuere Version laut winget, sonst leer | winget |
| `ProductCode` | MSI-Produkt-GUID | Registry |
| `RegistryKey` | Vollständiger Pfad des Uninstall-Schlüssels | Registry |
| `PackageFullName`, `PackageFamilyName` | MSIX-Paketkennung | Appx |
| `InstallLocation` | Installationsordner bzw. Ordner der gefundenen Datei | Registry, Appx, Portable |
| `InstallDate` | `yyyy-MM-dd`, falls bekannt | Registry |
| `UninstallString`, `QuietUninstallString` | Deinstallationsbefehle | Registry |
| `DisplayIcon` | Pfad zur Haupt-.exe bzw. zum Symbol | Registry |
| `Companions` | `PackageFullName` der Begleitpakete, die zu diesem Programm gehören (z. B. Kontextmenü-Erweiterung als Sparse Package) | Appx |
| `Flags` | Hinweise, siehe unten; bei Store-Apps `SparsePackage` | Appx, Portable |

### Nur portable Programme

| Feld | Bedeutung |
| --- | --- |
| `FilePath` | Hauptdatei |
| `CopyPaths` | Weitere Fundorte identischer Kopien (gleicher Name, Version, Größe, ggf. Hash) |
| `Sha256` | Hash der Hauptdatei; nur im gründlichen Scan |
| `SignatureStatus`, `Signer` | Ergebnis von `Get-AuthenticodeSignature` (`Valid`, `NotSigned`, `HashMismatch`, `NotTrusted`, …) |
| `Evidence` | Wodurch gefunden: `FileScan`, `UserAssist`, `Process`, `Autostart`, `ScheduledTask` |
| `LastRun`, `RunCount` | Letzter Start (UTC) und Startanzahl aus UserAssist, falls bekannt |
| `Flags` | Warnsignale, siehe unten |

Warnsignale und Hinweise (`Flags`):

| Wert | Bedeutung |
| --- | --- |
| `SparsePackage` | Store-Paket mit `AllowExternalContent`, das zu einem klassischen Programm gehört, aber nicht eindeutig zugeordnet werden konnte |
| `Unsigned` | Datei ist nicht signiert |
| `InvalidSignature` | Signatur vorhanden, aber ungültig oder nicht vertrauenswürdig |
| `InDownloadsOrTemp` | Liegt im Download- oder Temp-Ordner |
| `Autostart` | Startet automatisch (Run-Schlüssel, Autostart-Ordner, geplante Aufgabe) |
| `MultipleVersions` | Dasselbe Programm liegt in mehreren Ordnern in verschiedenen Versionen |

Leere Felder sind `null`.

## Installationsordner (`Resolve-InstallLocation`)

Ermittelt den Ordner eines Programms erst auf Anfrage (die App ruft es beim Aufklappen der Details auf und merkt sich das Ergebnis für die Sitzung). Die Quellen in dieser Reihenfolge:

| Quelle (`Source`) | Grundlage | Anzeige |
|---|---|---|
| `InstallerEntry` | `InstallLocation` aus dem Installer-Eintrag | „laut Installer-Eintrag“ |
| `AppPackage` | Ordner der Store-App | „laut App-Paket“ |
| `FileSearch` | Ordner der gefundenen Datei (portable Programme) | „laut Dateisuche“ |
| `DisplayIcon` | Ordner des Programmsymbols | „vermutlich, abgeleitet aus dem Programmsymbol“ |
| `UninstallCommand` | Ordner eines eigenen Deinstallationsprogramms (`unins*`, `uninstall*`, `setup*`) | „vermutlich, abgeleitet aus dem Deinstallationsbefehl“ |
| `MsiComponents` | gemeinsamer Ordner der `.exe`-Komponenten eines MSI-Produkts | „vermutlich, abgeleitet aus den installierten MSI-Komponenten“ |

Die ersten drei gelten als sicher (`Certain`). Die übrigen sind abgeleitet und zählen nur unter zwei Bedingungen:
- Im Ordner liegt ein Programm, also eine `.exe`, die kein Deinstallations- oder Setup-Programm ist.
- Der Ordner ist kein Zwischenspeicher des Installers.

Nie verwendet werden:
- `Windows\Installer`, `AppData\…\Installer`, `InstallShield Installation Information`, `ProgramData\Package Cache`, Temp- und Systemordner;
- `msiexec` und die Starter anderer Programme (z. B. Steam).

Ohne Ergebnis bleibt `Path` leer und `Reason` nennt den Grund als Meldung:

| Code | Bedeutung |
|---|---|
| `LocationNotFound` | Der Ordner aus dem Installer-Eintrag existiert nicht (Pfad in den Args). |
| `LocationNoProgramExe` | Im abgeleiteten Ordner liegt kein Programm. |
| `LocationOnlyInstallerCache` | Gefunden wurden nur Zwischenspeicher des Installers. |
| `LocationNoData` | Keine Quelle nennt einen Ordner. |

`CanOpen` ist bei Store-Apps (`WindowsApps`) falsch. Dort bietet die App nur „Pfad kopieren“ an.

## Wiedererkennung zwischen Scans

`Compare-InventorySnapshot` erkennt ein Programm in dieser Reihenfolge wieder: `RegistryKey`, `PackageFamilyName`, `WingetId`, `FilePath`, `Name`. Der Name steht bewusst zuletzt, weil er oft die Version enthält.

## Was ausgefiltert wird

- Registry: Einträge ohne `DisplayName`, `SystemComponent=1`, Unterpakete (`ParentKeyName`), Updates/Hotfixes (`ReleaseType`, `(KBnnnnnnn)` im Namen)
- Appx: Frameworks, `NonRemovable`, `SignatureKind=System`
- winget: Einträge, die einer gefilterten Registry-/Appx-Position entsprechen

## Begleitpakete (Sparse Packages)

Manche klassischen Programme registrieren zusätzlich ein Store-Paket, meist für das Kontextmenü (WinMerge, Edge, OneDrive). Erkennbar ist es an `AllowExternalContent` im Manifest. Es wird dem Programm unter `Companions` zugeordnet, wenn genau ein Registry-Programm passt: zuerst über den genau gleichen Namen, dann über den Anfang des Namens, dann über den Namen als ganze Wörter („OneDrive“ in „Microsoft OneDrive“), zuletzt über den Hersteller ohne Rechtsform. Ist die Zuordnung nicht eindeutig, bleibt das Paket mit `SparsePackage` als eigener Eintrag stehen.

## Portable Programme: Suche und Ausschlüsse

`Get-PortableSoftware` braucht keine Administratorrechte und führt keine Datei aus. Es liest nur, was in den Einstellungen aktiviert ist (siehe unten) oder als Parameter angegeben wird (`-Trace`, `-Path`, `-Drive`, `-IncludeTemp`, `-ComputeHash`; Ausschlüsse über `-ExcludePath` und `-NoSmartExclusion`). Ohne aktivierte Bereiche scannt es nichts. Die Ausschlüsse installierter Programme beruhen nur auf den aktivierten Inventar-Quellen.

Grundsatz: lieber ein Fehlalarm mehr als ein übersehenes Programm.

**Feste Ausschlüsse** (werden nie betreten):

- Windows-Ordner (`%windir%`). Der Dateiscan durchsucht damit auch `C:\Windows\Temp` derzeit nie, auch nicht mit `IncludeTemp`. Ausnahme bei Spuren: Prozesse, Autostarts und geplante Aufgaben, deren .exe in einem für Benutzer beschreibbaren Windows-Unterordner liegt (`C:\Windows\Temp`, `C:\Windows\Tasks`, `C:\Windows\Tracing`), werden immer gemeldet, unabhängig von `IncludeTemp`. Nur eigene Ausschlüsse (`ExcludePaths`) gehen vor.
- `%ProgramFiles%\WindowsApps`, `ProgramData\Microsoft`, `ProgramData\Package Cache`
- `%LOCALAPPDATA%\Packages`, `%LOCALAPPDATA%\Microsoft\WindowsApps`
- Auf jedem Laufwerk: `$Recycle.Bin` (Papierkorb), `System Volume Information`, `Windows.old`, `$WinREAgent`, `$SysReset`, `WindowsApps`, `WpSystem`, `XboxGames`
- Update-Zwischenspeicher von Electron-Apps (`%LOCALAPPDATA%\*-updater`)

**Ordner installierter Programme** (aus den aktivierten Inventar-Quellen): `InstallLocation`, Ordner des Deinstallationsprogramms und von `DisplayIcon`. Zu breite Angaben werden ignoriert, damit ein fehlerhafter Eintrag nicht ganze Bäume ausblendet: Laufwerkswurzeln, Benutzerprofil, Desktop, Dokumente, Downloads, AppData, `%LOCALAPPDATA%\Programs`, Temp-Ordner, Program Files (beide), Common Files (beide), `ProgramData` und der Windows-Ordner.

**Herstellerordner:** Unter `Program Files`, `Common Files` und `ProgramData` gilt ein Ordner wie `Program Files\Brother` als installiert, sobald eine darin gefundene Datei **gültig signiert** ist und ihr Hersteller (Versionsinfo oder Signierer) zugleich Herausgeber eines installierten Programms ist. Ohne gültige Signatur gibt es keine Herstellerzuordnung, denn die Herstellerangabe kann jeder setzen, und `ProgramData` ist für Benutzer beschreibbar.

**Abgleich über Name und Version** für Einträge ohne Pfad (z. B. Python): Eine Datei entspricht einem installierten Eintrag, wenn Name und Version (erste drei Teile) übereinstimmen und – falls die Datei einen Hersteller nennt – auch der Hersteller. Eine Datei mit Herstellerangabe zählt nur bei gültiger Signatur als Treffer; eine unsignierte bleibt sichtbar. Dateien ohne Herstellerangabe werden nur über Name und Version abgeglichen. Der Ordner des Treffers wird samt Unterordnern ausgeblendet (z. B. `Python313\Scripts\pip.exe`), außer er ist ein Sammelordner oder eine Scan-Wurzel (z. B. `D:\Tools`); dann verschwindet nur die Datei selbst. Sichtbar bleiben im ausgeblendeten Ordner Dateien mit eigenem Produktnamen **und** anderem Hersteller als der Treffer.

**Temp-Ordner:** Ohne `IncludeTemp` werden sie nicht durchsucht. Mit `IncludeTemp` verwirft der Dateiscan gültig signierte Dateien (meist Installer-Reste), aber nur, wenn **allein** der Dateiscan sie fand. Hat eine Datei eine Nutzungsspur (Process, UserAssist, Autostart, ScheduledTask), wird sie immer gemeldet.

**Zusammengefasst** werden: .exe-Dateien desselben Produkts in einem Ordner; Dateien in Unterordnern eines erkannten Programms (z. B. `resources\`, `node_modules\`), wobei das Programm nicht direkt in einem Sammelordner oder einer Scan-Wurzel liegen darf und Spuren sowie Warnsignale der Unterdateien übernimmt; identische Kopien.

Mit Administratorrechten (später): Amcache, BAM, Prefetch, Dienste.

## Einstellungen

Datei: `%APPDATA%\SoftwareInventory\settings.json`. Ohne Datei ist **alles aus**; jeder Bereich wird einzeln aktiviert (`Set-InventorySetting`). Es gibt keine Automatik nach Einsatzart.

```json
{
  "SchemaVersion": 1,
  "Usage": "Private",
  "Sources":  { "RegistryMachine": true, "RegistryUser": true, "Winget": true, "Appx": false },
  "Traces":   { "UserAssist": true, "Process": false, "Autostart": true, "ScheduledTask": false },
  "Services": { "WingetSearch": false, "GitHub": true, "NVD": false, "KEV": false, "EPSS": false },
  "Actions":  { "RestorePoint": false },
  "Maintenance": { "LogRetentionDays": 30, "LogMaxSizeMB": 100, "CirclStoreMaxSizeMB": 200 },
  "FileScan": {
    "Paths": ["%USERPROFILE%"], "Drives": ["D:"], "IncludeTemp": false, "ComputeHash": false,
    "ExcludePaths": ["%USERPROFILE%\\Projekte\\Builds"], "SmartExclusions": true
  }
}
```

| Bereich | Schalter |
| --- | --- |
| Inventar-Quellen (`Sources`) | `RegistryMachine` (HKLM, 64- und 32-Bit), `RegistryUser` (HKCU), `Winget`, `Appx` |
| Nutzungsspuren (`Traces`) | `UserAssist`, `Process`, `Autostart`, `ScheduledTask` |
| Externe Dienste (`Services`) | `WingetSearch` (winget-Suche für Programme ohne winget-ID), `GitHub` (Releases), `NVD`, `KEV`, `EPSS` (ab Etappe 2b). Gesendet werden nur Produkt- und Herstellernamen, Versionen und CVE-IDs, nie Pfade oder Benutzernamen. API-Schlüssel optional über `Set-ServiceCredential` (Windows-Anmeldeinformationsverwaltung, hat Vorrang) oder die Umgebungsvariablen `NVD_API_KEY` bzw. `GITHUB_TOKEN`; sie erscheinen nie in Protokollen, Snapshots oder Berichten. |
| Aktionen (`Actions`) | `RestorePoint`: vor jedem Aktualisieren/Deinstallieren einen Wiederherstellungspunkt anlegen (eigene UAC-Abfrage). Standardmäßig aus, keine Vorlage schaltet ihn ein. Siehe [AKTIONEN.md](AKTIONEN.md). |
| Bereinigung (`Maintenance`) | `LogRetentionDays` (Standard 30) und `LogMaxSizeMB` (Standard 100): Grenzen für Logs und Zwischenspeicher, die beim Laden des Moduls bereinigt werden; `CirclStoreMaxSizeMB` (Standard 200): eigene Grenze der CIRCL-Bestände. Scans sind ausgenommen. |
| Haltbarkeit (`CacheHours`) | `LatestVersion` (6), `NVD`, `EPSS`, `KEV` (je 24): Stunden, die Online-Ergebnisse wiederverwendet werden, 1–720 (siehe [SCHWACHSTELLEN.md](SCHWACHSTELLEN.md), „Zwischenspeicher“). |
| Dateiscan (`FileScan`) | `Paths` (Umgebungsvariablen erlaubt), `Drives`, `IncludeTemp`, `ComputeHash` |
| Ausschlüsse (`FileScan`) | `ExcludePaths`: eigene Ordner, die nie betreten werden – weder vom Dateiscan noch bei Spuren (Umgebungsvariablen erlaubt). `SmartExclusions`: `false` schaltet die Herstellerordner-Regel und den Abgleich über Name/Version ab (mehr Treffer); feste Systemausschlüsse und Ordner installierter Programme bleiben immer aktiv |
| `Usage` | `Private` oder `Company`; reine Information, schaltet nichts |

Vorlagen belegen die Schalter nur vor, wenn der Benutzer sie wählt; danach sind sie einzeln änderbar. `ExcludePaths`, `SmartExclusions` und die externen Dienste ändern Vorlagen nicht:

| Vorlage | Belegung |
| --- | --- |
| `Quick` | alle Quellen und Spuren, Dateiscan `%USERPROFILE%` ohne Temp, ohne Hash |
| `Thorough` | alle Quellen und Spuren, Dateiscan aller festen Laufwerke (zum Zeitpunkt der Wahl) einschließlich Temp, mit SHA256 |

`Get-PortableSoftware -ExcludePath …` und `-NoSmartExclusion` überschreiben die gespeicherten Werte für einen Aufruf. Ohne diese Parameter gelten die gespeicherten Werte – auch wenn andere Parameter wie `-Path` angegeben sind.

Unbekannte Werte in der Datei werden ignoriert. Fehlende Werte gelten als aus; ausgenommen sind `ExcludePaths` (leer), `SmartExclusions` (an) und die Grenzen unter `Maintenance` (30 Tage, 100 MB, 200 MB; ungültige Werte gelten als fehlend). `Set-InventorySetting -Reset` stellt genau diesen Ausgangszustand her.
