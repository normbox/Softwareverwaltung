# Versionsabgleich

`Test-SoftwareUpdate` nimmt Datensätze aus `Get-SoftwareInventory` oder `Get-PortableSoftware` und ermittelt die neueste Version.

```powershell
Get-SoftwareInventory | Test-SoftwareUpdate | Where-Object Status -eq Outdated
```

## Quellen (erster Treffer gewinnt)

| Reihenfolge | Quelle | Voraussetzung | Bestätigt |
| --- | --- | --- | --- |
| 1 | winget (`AvailableVersion` aus dem Inventar) | Inventarquelle `Winget` aktiv, Programm hat eine winget-ID | ja |
| 2 | GitHub Releases (`releases/latest`) | Katalogeintrag mit `GitHub.Repository`, Dienst `GitHub` aktiviert | ja |
| 3 | winget-Suche | Programm ohne winget-ID, mit Hersteller; Dienst `WingetSearch` aktiviert | **nein** – Zuordnung nur über Name und Hersteller |

Meldet winget für ein bekanntes Paket kein Update, gilt das Programm als aktuell. Herstellerregeln und KI-Recherche folgen in späteren Etappen.

### Regeln der winget-Suche

- Nicht für Store-Apps (MSIX): deren Updates kommen über den Microsoft Store.
- Gesucht wird nur in der Quelle `winget`. Ein Paket passt, wenn sein Name gleich dem Programmnamen ist oder mit ihm beginnt, gefolgt von Leerzeichen oder Klammer („PSPad editor (x64)“ passt zu „PSPad“), **und** der Hersteller übereinstimmt.
- Mehr als 5 Pakete mit passendem Namen gelten als mehrdeutig; dann werden keine Hersteller abgefragt.
- Mehrere passende Pakete sind nur eindeutig, wenn sie dieselbe Version haben (z. B. x64 und x86).
- Plausibilität: Verworfen wird ein Treffer, dessen Hauptversion kleiner ist als die installierte oder mehr als eine Hauptversion darüber liegt (z. B. installiert 1.0, gefunden 154.0).
- Ergebnisse werden 24 Stunden zwischengespeichert, Fehler der Suche nicht.

Externe Dienste sind standardmäßig aus (`Set-InventorySetting -Enable GitHub, WingetSearch`). GitHub-Antworten werden 12 Stunden zwischengespeichert (`%LOCALAPPDATA%\SoftwareInventory\cache`). Ohne Token gelten 60 GitHub-Anfragen pro Stunde; mit `GITHUB_TOKEN` 5.000. Ist das Limit erreicht, entfallen weitere GitHub-Abfragen im selben Lauf.

## Ergebnis (`SoftwareInventory.UpdateStatus`)

| Feld | Bedeutung |
| --- | --- |
| `Name`, `InstalledVersion` | aus dem Datensatz |
| `LatestVersion` | neueste gefundene Version |
| `Status` | `UpToDate`, `Outdated` oder `Unknown` |
| `Source` | `Winget`, `GitHub` oder `WingetSearch` |
| `Confirmed` | `false` bei Ergebnissen, die nur über Name und Hersteller gefunden wurden |
| `Reason` | bei `Unknown` immer gesetzt, z. B. „Dienst GitHub nicht aktiviert“, „Keine Versionsquelle bekannt“, „Installierte Version 'Unknown' nicht lesbar“ |
| `CatalogId` | zugeordneter Katalogeintrag (siehe [KATALOG.md](KATALOG.md)) |
| `Record` | der geprüfte Datensatz |

## Versionsvergleich

`Compare-SoftwareVersion a b` liefert `-1`, `0`, `1` oder `$null` (unbekannt).

- Zahlenteile numerisch, nachgestellte Nullen zählen nicht: `24.08` = `24.8.0.0`
- Präfixe `v` und `Version` sowie Zusätze `(x64)`, `+build…` und Commit-Hashes werden ignoriert
- Vorabversionen sind älter als die Release-Version: `dev`/`nightly` < `alpha` < `beta` < `pre`/`preview` < `rc` < Release
- Ein Patch-Buchstabe ist neuer: `1.1.1w` > `1.1.1`
- Alles andere hinter der Zahl (z. B. `7-Zip 26.05`, `1.4.2 Build 7`) und Bereiche wie `< 2026.3.1` ergeben „unbekannt“ – nie „gleich“
