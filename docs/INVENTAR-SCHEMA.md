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

`Get-PortableSoftware` braucht keine Administratorrechte und führt keine Datei aus. Es liest nur, was in den Einstellungen aktiviert ist (siehe unten) oder als Parameter angegeben wird (`-Trace`, `-Path`, `-Drive`, `-IncludeTemp`, `-ComputeHash`). Ohne aktivierte Bereiche scannt es nichts. Die Ausschlüsse installierter Programme beruhen nur auf den aktivierten Inventar-Quellen.

Nicht gemeldet werden:

- Windows-Ordner, `WindowsApps`, `WpSystem`, `XboxGames`, Papierkorb, `System Volume Information`, `ProgramData\Package Cache`
- Ordner installierter Programme: `InstallLocation`, Ordner des Deinstallationsprogramms und von `DisplayIcon`
- Herstellerordner unter `Program Files` und `ProgramData`, sobald eine Datei darin vom Herausgeber eines installierten Programms stammt
- Programme, die mit Name, Version (erste drei Teile) und – falls in der Datei angegeben – Hersteller einem installierten Eintrag entsprechen, samt Unterordnern (z. B. Python ohne Pfad im Uninstall-Eintrag)
- Update-Zwischenspeicher von Electron-Apps (`%LOCALAPPDATA%\*-updater`)
- Signierte Dateien in Temp-Ordnern (meist Installer-Reste)

Zusammengefasst werden: .exe-Dateien desselben Produkts in einem Ordner, Dateien in Unterordnern eines erkannten Programms (z. B. `resources\`, `node_modules\`) und identische Kopien.

Mit Administratorrechten (später): Amcache, BAM, Prefetch, Dienste.

## Einstellungen

Datei: `%APPDATA%\SoftwareInventory\settings.json`. Ohne Datei ist **alles aus**; jeder Bereich wird einzeln aktiviert (`Set-InventorySetting`). Es gibt keine Automatik nach Einsatzart.

```json
{
  "SchemaVersion": 1,
  "Usage": "Private",
  "Sources":  { "RegistryMachine": true, "RegistryUser": true, "Winget": true, "Appx": false },
  "Traces":   { "UserAssist": true, "Process": false, "Autostart": true, "ScheduledTask": false },
  "FileScan": { "Paths": ["%USERPROFILE%"], "Drives": ["D:"], "IncludeTemp": false, "ComputeHash": false }
}
```

| Bereich | Schalter |
| --- | --- |
| Inventar-Quellen (`Sources`) | `RegistryMachine` (HKLM, 64- und 32-Bit), `RegistryUser` (HKCU), `Winget`, `Appx` |
| Nutzungsspuren (`Traces`) | `UserAssist`, `Process`, `Autostart`, `ScheduledTask` |
| Dateiscan (`FileScan`) | `Paths` (Umgebungsvariablen erlaubt), `Drives`, `IncludeTemp`, `ComputeHash` |
| `Usage` | `Private` oder `Company`; reine Information, schaltet nichts |

Vorlagen belegen die Schalter nur vor, wenn der Benutzer sie wählt; danach sind sie einzeln änderbar:

| Vorlage | Belegung |
| --- | --- |
| `Quick` | alle Quellen und Spuren, Dateiscan `%USERPROFILE%` ohne Temp, ohne Hash |
| `Thorough` | alle Quellen und Spuren, Dateiscan aller festen Laufwerke (zum Zeitpunkt der Wahl) einschließlich Temp, mit SHA256 |

Unbekannte Werte in der Datei werden ignoriert, fehlende gelten als aus.
