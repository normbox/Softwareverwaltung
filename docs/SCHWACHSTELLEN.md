# Schwachstellenprüfung

`Get-SoftwareVulnerability` sucht bekannte Sicherheitslücken für erfasste Programme.

```powershell
Set-InventorySetting -Enable NVD, KEV, EPSS
Get-SoftwareInventory | Get-SoftwareVulnerability | Where-Object { $_.Vulnerabilities }
```

Die Funktion nimmt Datensätze aus `Get-SoftwareInventory` und `Get-PortableSoftware` sowie Ergebnisse von `Test-SoftwareUpdate` entgegen.

## Quellen

| Quelle | Zweck | Dienst | Zwischenspeicher |
| --- | --- | --- | --- |
| NVD CVE-API 2.0 | CVEs je CPE und Version, CVSS | `NVD` | 24 h je CPE und Seite |
| CISA KEV | aktiv ausgenutzte Lücken | `KEV` | 24 h (ganzer Katalog) |
| FIRST EPSS | Wahrscheinlichkeit einer Ausnutzung | `EPSS` | 24 h je Sammelabfrage |

Alle Dienste sind standardmäßig aus und werden einzeln aktiviert. Gesendet werden nur CPE-Namen mit Version (z. B. `cpe:2.3:a:7-zip:7-zip:24.8:*:*:*:*:*:*:*`) und CVE-IDs – keine Pfade, keine Benutzer- oder Rechnernamen.

Ohne NVD-API-Schlüssel ist die NVD auf 5 Anfragen pro 30 Sekunden begrenzt; das Modul wartet deshalb 6 Sekunden zwischen zwei Anfragen. Mit Schlüssel (kostenlos bei der NVD; gespeichert mit `Set-ServiceCredential -Service NVD` oder auf der Einstellungsseite der App, alternativ Umgebungsvariable `NVD_API_KEY`) sind es 0,6 Sekunden. Der Schlüssel wird nur als HTTP-Header gesendet und erscheint nie in Meldungen, Zwischenspeicher, Snapshots oder Berichten.

## Ablauf je Programm

1. **CPE bestimmen:** aus dem Katalog (`Cpe`, siehe [KATALOG.md](KATALOG.md)), sonst aus einer vom Benutzer bestätigten Zuordnung (siehe unten). Ohne beides gibt es keine Prüfung („Keine CPE zugeordnet“). `CpeSource` zeigt die Herkunft (`Catalog` oder `User`).
2. **NVD abfragen** mit der installierten Version. Die NVD wertet Versionsbereiche selbst aus; die Registry-Schreibweise (`24.8.0.0`) wird wie `24.08` behandelt.
3. **Lokal filtern:** Es zählen nur CVEs, bei denen das Produkt selbst mit `vulnerable=true` eingetragen ist und die Version im angegebenen Bereich liegt. Einträge, in denen das Produkt nur Umgebung ist (z. B. Python bei einer Lücke in PyGreSQL), entfallen. Nicht vergleichbare Bereichsgrenzen zählen als betroffen.
   Führt die NVD das Produkt **ohne jede Versionsgrenze** (`mozilla:firefox:*`, formal „alle Versionen“, meist Altdaten aus der Zeit vor sauberen Versionsbereichen), gilt:
   - CVE jünger als 5 Jahre → `PossiblyAffected` mit Hinweis „Versionsbereich in der NVD nicht angegeben“ (Ampel: Gelb mit Hinweis)
   - älter → `Informational` mit Hinweis „Altdaten ohne Versionsangabe“, ohne Ampelwirkung (z. B. Firefox-CVEs von 2007)
   - trifft zusätzlich ein Eintrag mit Versionsgrenze zu, ist die CVE normal `Affected`
4. **KEV abgleichen:** CVEs im KEV-Katalog werden markiert.
5. **KEV ohne NVD-Versionsdaten:** Seit 2024 analysiert die NVD viele neue CVEs verzögert; solche CVEs findet die CPE-Suche nicht. KEV-Einträge, die laut Katalog (`Kev`) zum Produkt gehören, werden deshalb zusätzlich einzeln in der NVD nachgeschlagen:
   - NVD hat Versionsdaten und die Version ist betroffen → `Affected`
   - NVD hat Versionsdaten und die Version ist nicht betroffen → entfällt
   - keine Versionsdaten oder NVD nicht aktiviert → `PossiblyAffected` mit Hinweis „Version nicht prüfbar“ (in der Ampel: Gelb mit Hinweis)
6. **EPSS** als eine Sammelabfrage für alle gefundenen CVEs.

## Ergebnis (`SoftwareInventory.VulnerabilityStatus`)

| Feld | Bedeutung |
| --- | --- |
| `Name`, `Version`, `CatalogId`, `Record` | geprüftes Programm |
| `CpeSource` | `Catalog` oder `User` (bestätigte Zuordnung) |
| `Cpe` | abgefragte CPE-Namen mit Version |
| `Status` | `Checked` (NVD abgefragt) oder `Unknown` |
| `Reason` | bei `Unknown` immer gesetzt: „Dienst NVD nicht aktiviert“, „Keine CPE zugeordnet …“, „Version '…' nicht lesbar“, „NVD-Anfragelimit erreicht“ … |
| `Notes` | Hinweise, z. B. „Dienst KEV nicht aktiviert“ |
| `Vulnerabilities` | Liste, KEV zuerst, dann nach CVSS absteigend; Hinweise (`Informational`) am Ende |

Je Schwachstelle (`SoftwareInventory.Vulnerability`): `CveId`, `Assessment` (`Affected`, `PossiblyAffected` oder `Informational`), `Note`, `Score`, `Severity`, `CvssVersion` (höchste vorhandene: 4.0 vor 3.1, 3.0, 2.0; bevorzugt die Bewertung der NVD), `Published`, `Description` (englisch, gekürzt), `Kev`, `KevDateAdded`, `KevRansomware`, `Epss`, `EpssPercentile`, `Url`.

## CPE für Programme ohne Katalogeintrag

```powershell
$gimp = Get-SoftwareInventory | Where-Object Name -like 'GIMP*'
$gimp | Find-CpeCandidate                                  # Vorschläge aus dem NVD-Wörterbuch, unbestätigt
$gimp | Set-CpeMapping -Cpe 'cpe:2.3:a:gimp:gimp'          # Zuordnung bestätigen
Get-CpeMapping                                             # bestätigte Zuordnungen anzeigen
Get-CpeMapping | Where-Object Name -like 'GIMP*' | Remove-CpeMapping
```

`Find-CpeCandidate` sucht den Programmnamen ohne Versionsangabe im CPE-Wörterbuch (Dienst `NVD`, Ergebnis 7 Tage zwischengespeichert) und bewertet, wie gut Produkt und Hersteller passen. Vorschläge werden nie automatisch verwendet. Bestätigte Zuordnungen liegen unter `%APPDATA%\SoftwareInventory\cpe-map.json` (Schlüssel: winget-ID, sonst Name ohne Version und Hersteller). Ein Katalogeintrag mit CPE hat Vorrang.

## Grenzen

- Geprüft werden nur Programme mit Katalogeintrag oder bestätigter CPE-Zuordnung.
- CVEs ohne CPE-Konfiguration in der NVD werden nur über KEV erfasst, nicht über die CPE-Suche.
- Verglichen wird die Versionsnummer; Zusatzfelder einer CPE (z. B. `3.15.0:alpha1`, Ausgabe `esr`) werden nicht ausgewertet. Im Zweifel entsteht ein Fehlalarm, kein übersehener Treffer.
- OSV und GitHub Security Advisories sind noch nicht angebunden.
