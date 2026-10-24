# Inventar-Schema

Ein Snapshot ist eine JSON-Datei unter `%LOCALAPPDATA%\SoftwareInventory\scans\<yyyyMMdd-HHmmss-fff>.json` (Zeit in UTC).

```json
{
  "SchemaVersion": 1,
  "CreatedAt": "2026-10-24T13:36:00.708Z",
  "ModuleVersion": "0.1.0",
  "Records": [ { "Name": "7-Zip 26.05 (x64)", "...": "..." } ]
}
```

Snapshots mit einer höheren `SchemaVersion`, als das Modul kennt, werden beim Laden übersprungen. Ändert sich das Schema inkompatibel, wird die Version erhöht.

## Datensatz (`SoftwareInventory.SoftwareRecord`)

| Feld | Bedeutung | Quelle |
| --- | --- | --- |
| `Name` | Anzeigename; bei Store-Apps aus winget, sonst technischer Paketname | alle |
| `Publisher` | Hersteller | Registry, Appx |
| `Version` | Installierte Version, unverändert übernommen (Normalisierung folgt in Etappe 2) | alle |
| `InstallType` | `MSI`, `EXE`, `MSIX` oder `Winget` (nur in winget bekannt) | |
| `Scope` | `Machine` oder `User` | Registry, Appx |
| `Architecture` | `X64`, `X86`, `Arm64`, `Neutral` | Registry, Appx |
| `Sources` | Liste der Quellen, die das Programm kennen: `Registry`, `Appx`, `Winget` | |
| `WingetId`, `WingetSource` | Paket-ID und Katalog (`winget`, `msstore`); nur bei Katalogpaketen | winget |
| `AvailableVersion` | Neuere Version laut winget, sonst leer | winget |
| `ProductCode` | MSI-Produkt-GUID | Registry |
| `RegistryKey` | Vollständiger Pfad des Uninstall-Schlüssels | Registry |
| `PackageFullName`, `PackageFamilyName` | MSIX-Paketkennung | Appx |
| `InstallLocation` | Installationsordner | Registry, Appx |
| `InstallDate` | `yyyy-MM-dd`, falls bekannt | Registry |
| `UninstallString`, `QuietUninstallString` | Deinstallationsbefehle | Registry |

Leere Felder sind `null`.

## Wiedererkennung zwischen Scans

`Compare-InventorySnapshot` erkennt ein Programm in dieser Reihenfolge wieder: `RegistryKey`, `PackageFamilyName`, `WingetId`, `Name`. Der Name steht bewusst zuletzt, weil er oft die Version enthält.

## Was ausgefiltert wird

- Registry: Einträge ohne `DisplayName`, `SystemComponent=1`, Unterpakete (`ParentKeyName`), Updates/Hotfixes (`ReleaseType`, `(KBnnnnnnn)` im Namen)
- Appx: Frameworks, `NonRemovable`, `SignatureKind=System`
- winget: Einträge, die einer gefilterten Registry-/Appx-Position entsprechen
