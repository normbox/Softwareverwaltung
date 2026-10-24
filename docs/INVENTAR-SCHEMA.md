# Inventar-Schema

Ein Snapshot ist eine JSON-Datei unter `%LOCALAPPDATA%\SoftwareInventory\scans\<yyyyMMdd-HHmmss-fff>.json` (Zeit in UTC).

```json
{
  "SchemaVersion": 2,
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

Warnsignale (`Flags`):

| Wert | Bedeutung |
| --- | --- |
| `Unsigned` | Datei ist nicht signiert |
| `InvalidSignature` | Signatur vorhanden, aber ungültig oder nicht vertrauenswürdig |
| `InDownloadsOrTemp` | Liegt im Download- oder Temp-Ordner |
| `Autostart` | Startet automatisch (Run-Schlüssel, Autostart-Ordner, geplante Aufgabe) |
| `MultipleVersions` | Dasselbe Programm liegt in mehreren Ordnern in verschiedenen Versionen |

Leere Felder sind `null`.

## Wiedererkennung zwischen Scans

`Compare-InventorySnapshot` erkennt ein Programm in dieser Reihenfolge wieder: `RegistryKey`, `PackageFamilyName`, `WingetId`, `FilePath`, `Name`. Der Name steht bewusst zuletzt, weil er oft die Version enthält.

## Was ausgefiltert wird

- Registry: Einträge ohne `DisplayName`, `SystemComponent=1`, Unterpakete (`ParentKeyName`), Updates/Hotfixes (`ReleaseType`, `(KBnnnnnnn)` im Namen)
- Appx: Frameworks, `NonRemovable`, `SignatureKind=System`
- winget: Einträge, die einer gefilterten Registry-/Appx-Position entsprechen

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
| Dateiscan (`FileScan`) | `Paths` (Umgebungsvariablen erlaubt), `Drives`, `IncludeTemp`, `ComputeHash` |
| Ausschlüsse (`FileScan`) | `ExcludePaths`: eigene Ordner, die nie betreten werden – weder vom Dateiscan noch bei Spuren (Umgebungsvariablen erlaubt). `SmartExclusions`: `false` schaltet die Herstellerordner-Regel und den Abgleich über Name/Version ab (mehr Treffer); feste Systemausschlüsse und Ordner installierter Programme bleiben immer aktiv |
| `Usage` | `Private` oder `Company`; reine Information, schaltet nichts |

Vorlagen belegen die Schalter nur vor, wenn der Benutzer sie wählt; danach sind sie einzeln änderbar. `ExcludePaths` und `SmartExclusions` ändern Vorlagen nicht:

| Vorlage | Belegung |
| --- | --- |
| `Quick` | alle Quellen und Spuren, Dateiscan `%USERPROFILE%` ohne Temp, ohne Hash |
| `Thorough` | alle Quellen und Spuren, Dateiscan aller festen Laufwerke (zum Zeitpunkt der Wahl) einschließlich Temp, mit SHA256 |

`Get-PortableSoftware -ExcludePath …` und `-NoSmartExclusion` überschreiben die gespeicherten Werte für einen Aufruf. Ohne diese Parameter gelten die gespeicherten Werte – auch wenn andere Parameter wie `-Path` angegeben sind.

Unbekannte Werte in der Datei werden ignoriert. Fehlende Werte gelten als aus; ausgenommen sind `ExcludePaths` (leer) und `SmartExclusions` (an), die sich wie bisher verhalten. `Set-InventorySetting -Reset` stellt genau diesen Ausgangszustand her.
