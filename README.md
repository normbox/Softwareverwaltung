# Softwareverwaltung
Inventarisierung installierter Windows-Software mit Versions-/Sicherheitscheck und KI-Berater

Stand: Etappe 1b (portable Programme). Konzept: [docs/KONZEPT.md](docs/KONZEPT.md)

## Inventar-Modul ausprobieren

Voraussetzung: PowerShell 7.6 und optional das Modul `Microsoft.WinGet.Client` (siehe [docs/ENTWICKLUNG.md](docs/ENTWICKLUNG.md)). Administratorrechte sind nicht nötig.

```powershell
Import-Module ./src/SoftwareInventory

# Standardmäßig ist alles aus. Bereiche einzeln aktivieren oder eine Vorlage wählen:
Set-InventorySetting -Enable RegistryMachine, RegistryUser, Winget, Appx
Set-InventorySetting -Preset Quick                           # alle Quellen und Spuren, Dateiscan im Benutzerprofil
Get-InventorySetting                                         # aktuelle Auswahl anzeigen

Get-SoftwareInventory | Format-Table Name, Version, AvailableVersion, Sources
Get-SoftwareInventory | Where-Object AvailableVersion        # Programme mit Update laut winget
Get-SoftwareInventory | Save-InventorySnapshot               # Scan speichern
Compare-InventorySnapshot                                    # Unterschied der letzten beiden Scans

# Portable und nicht registrierte Programme
Get-PortableSoftware | Format-Table Name, Version, Flags, FilePath   # mit den aktivierten Bereichen
Get-ScanDrive                                                        # wählbare Laufwerke
Get-PortableSoftware -Drive C, D -ComputeHash                        # einmalig ganze Laufwerke, mit SHA256

# Installiertes und Portables in einem Snapshot
@(Get-SoftwareInventory) + @(Get-PortableSoftware) | Save-InventorySnapshot
```

Aufbau eines Datensatzes und der Snapshot-Dateien: [docs/INVENTAR-SCHEMA.md](docs/INVENTAR-SCHEMA.md)
