# Softwareverwaltung
Inventarisierung installierter Windows-Software mit Versions-/Sicherheitscheck und KI-Berater

Stand: Etappe 1 (Inventar-Modul). Konzept: [docs/KONZEPT.md](docs/KONZEPT.md)

## Inventar-Modul ausprobieren

Voraussetzung: PowerShell 7.6 und optional das Modul `Microsoft.WinGet.Client` (siehe [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md)). Administratorrechte sind nicht nötig.

```powershell
Import-Module ./src/SoftwareInventory

Get-SoftwareInventory | Format-Table Name, Version, AvailableVersion, Sources
Get-SoftwareInventory | Where-Object AvailableVersion        # Programme mit Update laut winget
Get-SoftwareInventory | Save-InventorySnapshot               # Scan speichern
Compare-InventorySnapshot                                    # Unterschied der letzten beiden Scans
```

Aufbau eines Datensatzes und der Snapshot-Dateien: [docs/INVENTAR-SCHEMA.md](docs/INVENTAR-SCHEMA.md)
