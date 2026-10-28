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
| `CpeCheck` | bei `Cpe` | Wie die Zuordnung geprüft wurde: `CheckedAt` (Datum `JJJJ-MM-TT`), `Evidence` (Links, mindestens die CPE in der NVD) und `Note` (kurz, was geprüft wurde). Maßstab im Abschnitt [CPE prüfen](#cpe-prüfen). |
| `CpeVersionPattern` | nein | regulärer Ausdruck mit Gruppe `(?<version>…)`, der eine produkteigene Versionsangabe vor der NVD-Abfrage umrechnet. Beispiel Python: Die Dateiversion `3.13.15150.0` bedeutet 3.13.15 (Release-Stufe und Serie sind angehängt). Passt das Muster nicht, wird die Version unverändert verwendet. |
| `Kev` | nein | Zuordnung zum CISA-KEV-Katalog: `Vendor` (exakt wie `vendorProject` im Feed, Groß-/Kleinschreibung egal) und `ProductPattern` (regulärer Ausdruck auf `product`, da der Feed Sammelangaben wie „Firefox, Firefox ESR, and Thunderbird“ enthält). Gleicht KEV-Einträge aus, die in der NVD noch keine Versionsdaten haben. |
| `KevFixed` | nein | „Behoben ab“ je KEV-Lücke: `{ "CVE-…": "erste nicht betroffene Version" }`, z. B. `{ "CVE-2025-0411": "24.09" }` für 7-Zip. Gilt nur, wenn die NVD nicht entscheiden kann (Dienst aus, nicht abrufbar, keine Versionsdaten): gleiche oder neuere Version → Treffer widerlegt (Grund in der Ampel), ältere → sicher betroffen. Quelle angeben (NVD-Versionsbereich oder Herstellerhinweis). Braucht `Kev`. |

## CPE prüfen

Eine CPE kommt nur in den Katalog, wenn alle Punkte zutreffen. Was geprüft wurde, steht im Eintrag unter `CpeCheck`, damit jeder Beitrag denselben Maßstab hat.

1. **Die CPE gibt es.** Die Abfrage `https://services.nvd.nist.gov/rest/json/cpes/2.0?cpeMatchString=<cpe>` liefert Einträge, die nicht alle veraltet (`deprecated`) sind. Als Beleg dient der Link zur Suche in der NVD: `https://nvd.nist.gov/products/cpe/search/results?namingFormat=2.3&keyword=<cpe>`.
2. **Es ist dasselbe Produkt.** Der Titel in der NVD bezeichnet genau dieses Programm, nicht ein Plugin, eine Bibliothek, einen Dienst oder ein gleichnamiges Produkt eines anderen Herstellers. Beispiele für falsche Treffer aus der Stichprobe: „Jan“ → `janino_project:janino`, „Claude“ → `anthropic:claude_code`, „Paint“ → `microsoft:paint_3d`.
3. **Die Versionen passen.** Die Versionen in der NVD haben dieselbe Form wie die installierte Version (z. B. `4.6.6` und `4.6.6`). Führt die NVD Jahreszahlen oder Build-Nummern, die man nicht umrechnen kann, wird die CPE nicht aufgenommen. Lässt es sich umrechnen, gehört ein `CpeVersionPattern` dazu.
4. **Eine Lücke stichprobenhaft ansehen,** wenn es welche gibt: `https://services.nvd.nist.gov/rest/json/cves/2.0?virtualMatchString=<cpe>`. Betrifft sie wirklich dieses Programm unter Windows? Gibt es keine Lücke, steht das in `Note`.
5. **Mehrere Herstellernamen:** Führt die NVD dasselbe Produkt unter mehreren Herstellern (z. B. `notepad-plus-plus` und `don_ho`), kommen alle Namen in `Cpe`.

Beispiel:

```json
"Cpe": ["cpe:2.3:a:wireshark:wireshark"],
"CpeCheck": {
  "CheckedAt": "2026-10-28",
  "Evidence": ["https://nvd.nist.gov/products/cpe/search/results?namingFormat=2.3&keyword=cpe%3A2.3%3Aa%3Awireshark%3Awireshark"],
  "Note": "NVD-Titel „Wireshark 4.6.x“, Versionen dreistellig wie installiert; CVE-Stichprobe betrifft Wireshark selbst."
}
```

Vorschläge von Nutzern („Vorschlag melden“ in der App, Issue-Formular `cpe-zuordnung`) werden nach demselben Maßstab geprüft, bevor sie aufgenommen werden. Die App übernimmt Vorschläge nie automatisch.

## Herstelleraliase für Vorschläge

`src/SoftwareInventory/Data/cpe-vendor-alias.json` hilft nur bei der Bewertung von Vorschlägen (`Find-CpeCandidate`), wenn der Herausgeber anders heißt als der Hersteller in der NVD, z. B. „Irfan Skiljan“ → `irfanview`. Schlüssel ist das erste Wort des Herausgebers (klein). Ein Alias ordnet nie selbst zu.

## Zuordnung

1. winget-ID
2. PackageFamilyName
3. Name-Muster **und** Hersteller (bei portablen Programmen auch der Signierer)

Ein Name allein ordnet nie zu, damit gleichnamige Programme anderer Herausgeber (z. B. eine Explorer-Erweiterung „WinMerge“) keine falschen Update-Meldungen auslösen.

## Neuen Eintrag beitragen

- Nur Produkte mit verlässlicher Quelle: GitHub-Releases des Herstellers, kein Fork.
- Den Tag der aktuellen Version prüfen: `https://api.github.com/repos/<owner>/<repo>/releases/latest`.
- `Invoke-Pester ./tests/Unit/Catalog.Tests.ps1` prüft alle Dateien (Pflichtfelder, gültige Muster, keine doppelten IDs).
