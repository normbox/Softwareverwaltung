# Katalog

Der Katalog liegt unter `src/SoftwareInventory/Catalog/` und wird mit dem Modul ausgeliefert. Pro Produkt gibt es eine JSON-Datei. Er ordnet erfasste Programme einem Produkt zu und nennt Quellen für die neueste Version. CPE-Angaben für die Sicherheitsprüfung kommen mit Etappe 2b hinzu.

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

## Zuordnung

1. winget-ID
2. PackageFamilyName
3. Name-Muster **und** Hersteller (bei portablen Programmen auch der Signierer)

Ein Name allein ordnet nie zu, damit gleichnamige Programme anderer Herausgeber (z. B. eine Explorer-Erweiterung „WinMerge“) keine falschen Update-Meldungen auslösen.

## Neuen Eintrag beitragen

- Nur Produkte mit verlässlicher Quelle: GitHub-Releases des Herstellers, kein Fork.
- Den Tag der aktuellen Version prüfen: `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
- `Invoke-Pester ./tests/Unit/Catalog.Tests.ps1` prüft alle Dateien (Pflichtfelder, gültige Muster, keine doppelten IDs).
