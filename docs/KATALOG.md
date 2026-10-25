# Katalog

Der Katalog liegt unter `src/SoftwareInventory/Catalog/` und wird mit dem Modul ausgeliefert. Pro Produkt gibt es eine JSON-Datei. Er ordnet erfasste Programme einem Produkt zu und nennt Quellen für die neueste Version (GitHub) und für Schwachstellen (CPE, KEV).

## Aufbau

```json
{
  "Id": "notepad-plus-plus",
  "Name": "Notepad++",
  "Match": {
    "WingetId": ["Notepad++.Notepad++"],
    "PackageFamilyName": [],
    "NamePattern": "^Notepad\\+\\+",
    "Publisher": ["Notepad++ Team", "Don HO"]
  },
  "GitHub": { "Repository": "notepad-plus-plus/notepad-plus-plus", "TagPattern": "^v?(?<version>\\d.*)$" }
}
```

| Feld | Pflicht | Bedeutung |
| --- | --- | --- |
| `Id` | ja | gleich dem Dateinamen ohne `.json`; Kleinbuchstaben, Ziffern, Bindestriche |
| `Name` | ja | Anzeigename des Produkts |
| `Match.WingetId` | eins von dreien | winget-Paket-IDs (stärkste Zuordnung) |
| `Match.PackageFamilyName` | eins von dreien | für Store-/MSIX-Apps |
| `Match.NamePattern` | eins von dreien | regulärer Ausdruck auf den Programmnamen; nur zusammen mit `Publisher` |
| `Match.Publisher` | bei `NamePattern` | erlaubte Hersteller; verglichen wird das erste Wort (mind. 3 Zeichen), z. B. „Acronis International GmbH“ → `acronis` |
| `GitHub.Repository` | nein | `owner/repo`; abgefragt wird `releases/latest` (ohne Vorabversionen) |
| `GitHub.TagPattern` | nein | regulärer Ausdruck mit Gruppe `(?<version>…)`, falls der Tag nicht `v1.2.3` oder `1.2.3` lautet (z. B. `Audacity-4.0.1`) |
| `Cpe` | nein | CPE-Namen ohne Version, z. B. `cpe:2.3:a:videolan:vlc_media_player`; Sonderzeichen wie in der NVD mit `\` (`notepad\+\+`). Mehrere Einträge, wenn die NVD das Produkt unter verschiedenen Herstellern führt. Prüfen unter `https://services.nvd.nist.gov/rest/json/cpes/2.0?cpeMatchString=<cpe>` |
| `CpeVersionPattern` | nein | regulärer Ausdruck mit Gruppe `(?<version>…)`, der eine produkteigene Versionsangabe vor der NVD-Abfrage umrechnet. Beispiel Python: Die Dateiversion `3.13.15150.0` bedeutet 3.13.15 (Release-Stufe und Serie sind angehängt). Passt das Muster nicht, wird die Version unverändert verwendet. |
| `Kev` | nein | Zuordnung zum CISA-KEV-Katalog: `Vendor` (exakt wie `vendorProject` im Feed, Groß-/Kleinschreibung egal) und `ProductPattern` (regulärer Ausdruck auf `product`, da der Feed Sammelangaben wie „Firefox, Firefox ESR, and Thunderbird“ enthält). Gleicht KEV-Einträge aus, die in der NVD noch keine Versionsdaten haben. |

## Zuordnung

1. winget-ID
2. PackageFamilyName
3. Name-Muster **und** Hersteller (bei portablen Programmen auch der Signierer)

Ein Name allein ordnet nie zu, damit gleichnamige Programme anderer Herausgeber (z. B. eine Explorer-Erweiterung „WinMerge“) keine falschen Update-Meldungen auslösen.

## Neuen Eintrag beitragen

- Nur Produkte mit verlässlicher Quelle: GitHub-Releases des Herstellers, kein Fork.
- Den Tag der aktuellen Version prüfen: `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
- `Invoke-Pester ./tests/Unit/Catalog.Tests.ps1` prüft alle Dateien (Pflichtfelder, gültige Muster, keine doppelten IDs).
