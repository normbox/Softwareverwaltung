# Schwachstellenprüfung

`Get-SoftwareVulnerability` sucht bekannte Sicherheitslücken für erfasste Programme.

```powershell
Set-InventorySetting -Enable NVD, CIRCL, KEV, EPSS
Get-SoftwareInventory | Get-SoftwareVulnerability | Where-Object { $_.Vulnerabilities }
```

Die Funktion nimmt Datensätze aus `Get-SoftwareInventory` und `Get-PortableSoftware` sowie Ergebnisse von `Test-SoftwareUpdate` entgegen.

## Quellen

| Quelle | Zweck | Dienst | Zwischenspeicher |
| --- | --- | --- | --- |
| NVD CVE-API 2.0 | CVEs je CPE und Version, CVSS | `NVD` | Standard 24 h je CPE und Seite |
| CIRCL Vulnerability-Lookup | CVE-Datensätze (CVE 5) je Hersteller und Produkt, Versionsauswertung lokal | `CIRCL` | Bestand je Produkt, Standard 24 h, dann nur Änderungen nachladen; alle 30 Tage vollständig |
| CISA KEV | aktiv ausgenutzte Lücken | `KEV` | Standard 24 h (ganzer Katalog) |
| FIRST EPSS | Wahrscheinlichkeit einer Ausnutzung | `EPSS` | Standard 24 h je CVE, eine Datei für alle CVEs |

### Zwischenspeicher

- **Haltbarkeit:** Die Haltbarkeit je Quelle steht in der Einstellung `CacheHours` mit `LatestVersion` (GitHub und winget-Suche, Standard 6), `NVD`, `CIRCL`, `EPSS` und `KEV` (je Standard 24). Erlaubt sind 1 bis 720 Stunden. Die CPE-Suche bleibt fest bei 7 Tagen. Geprüft wird beim Lesen, eine Änderung wirkt also sofort.
- **Neu prüfen ohne Cache:** `Get-SecurityRating -Refresh`, ebenso `Test-SoftwareUpdate` und `Get-SoftwareVulnerability`. Jede Antwort wird pro Lauf einmal frisch geholt, der KEV-Katalog also einmal. Bei CIRCL heißt das: der Bestand des Produkts wird vollständig neu geladen.
- **CIRCL-Bestand:** Je Produkt (Hersteller und Produkt der CPE, unabhängig von der Version) eine Datei `cache\CIRCL\store-<Hash>.json` mit den ausgewerteten Feldern der CVE-Datensätze (Metadaten, `affected`, englische Beschreibung, CVSS). Jünger als `CacheHours.CIRCL`: keine Anfrage. Älter: nur die seither geänderten Datensätze mit `since=<Tag des letzten Abrufs>` (CIRCL filtert nach `dateUpdated`, also kommen auch nachgetragene Versionsbereiche alter CVEs an); gleiche CVE-ID ersetzt den alten Datensatz, zurückgezogene (`state` nicht `PUBLISHED`) fallen heraus. Vollständig geladen wird, wenn der Bestand fehlt (z. B. aufgeräumt), unlesbar ist, der letzte vollständige Abruf mehr als **30 Tage** zurückliegt (fest im Modul) oder bei Neu prüfen ohne Cache. Geschrieben wird nur nach einem ganz gelungenen Abruf, Bestand und Abrufdatum gemeinsam; bricht das Nachladen ab, bleibt das Datum stehen und der alte Bestand gilt als veraltet weiter. Ein Ergebnis aus einem halben Bestand gibt es nie.
- **EPSS-Werte:** Eine Datei `cache\EPSS\scores.json` mit einem Eintrag je CVE samt Abrufzeit. Abgefragt werden nur fehlende oder abgelaufene CVEs (Sammelabfragen zu je 100); CVEs ohne EPSS-Wert werden ebenfalls vermerkt, damit sie nicht bei jedem Scan neu abgefragt werden. Geschrieben wird nur, wenn etwas abgefragt wurde, direkt ohne Zwischendatei. Ist die Datei unlesbar (z. B. nach einem Abbruch beim Schreiben), gilt sie als leer und wird neu abgefragt; das steht im Fehlerprotokoll (`logs\app-errors-<Datum>.log`), eine Meldung gibt es nicht. „Geprüft vor …“ berücksichtigt das tatsächliche Alter der EPSS-Werte eines Programms (ältester Abruf seiner CVEs). Frühere Dateien je Sammelabfrage werden nicht mehr gelesen und laufen über die normale Bereinigung aus.
- **Neue Versuche je Seite:** Scheitert eine Seite der CIRCL-Suche an einem Netzwerkfehler, einer Zeitüberschreitung oder einem Serverfehler (5xx), wird sie nach 5 und nach 15 Sekunden noch einmal angefragt (sichtbar in der zweiten Zeile der Anzeige). Anfragelimit (429) wartet die gemeinsame Abfrageschicht selbst ab; 404 und andere 4xx werden nicht wiederholt. Scheitert ein vollständiger Abruf endgültig, steht er in `logs\data-notes\<Datum>.jsonl` (Code `CirclFullFetchFailed`, Produkt, Seite x/y, Fehler); es wird kein Bestand gespeichert.
- **Offline oder am Anfragelimit:** Dann gilt ein abgelaufener Eintrag weiter. `CheckStale` ist dann wahr, die App kennzeichnet „Geprüft“ dezent als veraltet.
- **Prüfzeitpunkt:** `CheckedAt` an `UpdateStatus`, `VulnerabilityStatus` und `SecurityRating` ist der älteste benutzte Abruf (UTC). In der Ampel ist es das Ältere beider Prüfungen, `UpdateCheckedAt` und `VulnerabilityCheckedAt` nennen beide einzeln. Wurde nichts online geprüft, bleibt `CheckedAt` leer.
- **Gezielt verwerfen:** Ein Index je Programm und Version (`cache\index`) merkt sich die benutzten Einträge. `Get-SecurityRating` schreibt ihn am Ende einmal je Programm (Versions- und Lückenprüfung zusammen, auch nach einem Abbruch für das bis dahin Geprüfte) und nur, wenn sich die benutzten Einträge geändert haben; ein Scan innerhalb der Haltbarkeit schreibt also nichts. Viele unveränderte Neuschreibungen in kurzer Folge können Verhaltensschutz-Programme auslösen. `Clear-CheckCache` verwirft die Einträge eines Programms, der gemeinsame KEV-Katalog und die EPSS-Werte bleiben erhalten. Der CIRCL-Bestand bleibt ebenfalls (er gilt für alle Versionen), wird aber bei der nächsten Prüfung per `since` nachgeladen; die neue Version wird dabei neu bewertet. Nach einer Deinstallation räumt ihn die normale Bereinigung auf. Die App ruft das nach jeder Aktion auf.
- **Dauer schätzen:** `Get-RefreshEstimate` schätzt die Dauer einer Prüfung ohne Cache: NVD-Anfragen mit 6 Sekunden Abstand ohne Schlüssel bzw. 0,6 Sekunden mit Schlüssel. Mit CIRCL zählt der vollständige Abruf aller Seiten je CPE (3 bzw. 1,5 Sekunden je Seite); die Seitenzahl kommt aus der Größe des vorhandenen Bestands (etwa 48 KB je Seite), ohne Bestand zählt eine Seite (`CirclUnknown`). Je CPE läuft es nacheinander: NVD-Versionssuche, CIRCL-Seiten, NVD-Abgleich. `NeedsConfirmation` ist wahr, wenn NVD aktiviert ist und kein Schlüssel hinterlegt ist (`ConfirmReason` `NvdWithoutKey`) oder die Schätzung über 5 Minuten liegt (`LongDuration`). Dann fragt die App vor „Ohne Cache scannen“ nach und nennt die geschätzte Dauer.

Alle Dienste sind standardmäßig aus und werden einzeln aktiviert. Gesendet werden nur CPE-Namen mit Version (z. B. `cpe:2.3:a:7-zip:7-zip:24.8:*:*:*:*:*:*:*`), an CIRCL nur Hersteller und Produkt ohne Version, und CVE-IDs – keine Pfade, keine Benutzer- oder Rechnernamen.

**Anfragelimit (429):** Antwortet ein Dienst mit HTTP 429 und `Retry-After` bis 60 Sekunden, wartet das Modul einmal so lange und wiederholt die Anfrage. Sonst gilt ein vorhandener, auch abgelaufener Eintrag aus dem Zwischenspeicher; ohne ihn ist der Grund `RateLimit`.

Ohne NVD-API-Schlüssel ist die NVD auf 5 Anfragen pro 30 Sekunden begrenzt; das Modul wartet deshalb 6 Sekunden zwischen zwei Anfragen. Mit Schlüssel (kostenlos bei der NVD; gespeichert mit `Set-ServiceCredential -Service NVD` oder auf der Einstellungsseite der App, alternativ Umgebungsvariable `NVD_API_KEY`) sind es 0,6 Sekunden. Der Schlüssel wird nur als HTTP-Header gesendet und erscheint nie in Meldungen, Zwischenspeicher, Snapshots oder Berichten.

## Ablauf je Programm

1. **CPE bestimmen:** aus dem Katalog (`Cpe`, siehe [KATALOG.md](KATALOG.md)), sonst aus einer vom Benutzer bestätigten Zuordnung (siehe unten). Ohne beides gibt es keine Prüfung („Keine CPE zugeordnet“). `CpeSource` zeigt die Herkunft (`Catalog` oder `User`).
2. **NVD abfragen** mit der installierten Version. Die NVD wertet Versionsbereiche selbst aus; die Registry-Schreibweise (`24.8.0.0`) wird wie `24.08` behandelt.
3. **Lokal filtern:** Es zählen nur CVEs, bei denen das Produkt selbst mit `vulnerable=true` eingetragen ist und die Version im angegebenen Bereich liegt. Einträge, in denen das Produkt nur Umgebung ist (z. B. Python bei einer Lücke in PyGreSQL), entfallen.
   **Nicht vergleichbare Bereichsgrenzen** ergeben nie „betroffen“, sondern „möglicherweise betroffen“ mit Grund „Versionsgrenze nicht vergleichbar (Bereich, installiert Version)“ (`VersionBoundNotComparable`), bei CVEs älter als 5 Jahre nur einen Hinweis ohne Ampelwirkung; steht die CVE in KEV, bleibt sie gelb. Dieselbe Regel gilt für CIRCL (`Compare-VersionBound`). Nicht vergleichbar sind:
   - Commit-Kennungen als Grenze,
   - ein Datum als Grenze (`2025-01-13`, gültiges `20250113`; `2025.01.13` nur, wenn die installierte Version normal ist, also Hauptversion unter 1900) gegenüber einer normalen Version, z. B. FFmpeg 9.0.2 gegen „< 2025-01-13“ (Fall CVE-2025-25469),
   - unlesbare Angaben.

   Datumsartige Versionen (yt-dlp `2025.01.15`) bleiben vergleichbar, auch gegen Datumsgrenzen; als Datum gilt eine installierte Version nur mit drei Teilen, Jahr ab 1900, Monat 1–12 und gültigem Tag. Build-Nummern wie `2302.1.0` oder `1903` und Jahresversionen wie Foxit `2025.2.0.33046` sind kein Datum. Kein Abgleich mit Erscheinungsdaten. Eine vergleichbare Grenze, die die Version ausschließt, gilt weiter als „nicht betroffen“, und ein echtes „betroffen“ der anderen Quelle geht vor. Jeder Fall steht in `logs\data-notes\` (Code `VersionBoundNotComparable`).
   **Laut Beschreibung nicht betroffen:** Hat keine Quelle entschieden (nur „möglicherweise betroffen“ oder Hinweis, kein Widerspruch) und steht in der Beschreibung „<Produkt> before X“ bzw. „prior to X“, wird die CVE herabgestuft, wenn die installierte Version vergleichbar und nicht kleiner als X ist. Sie steht dann in `DescriptionFixed` („Laut Beschreibung nicht betroffen (unbestätigt)“), ohne Ampelwirkung, und in `logs\data-notes\` (Code `DescriptionSaysFixed`). Bedingungen: genau eine Versionsangabe im Text, der Produktname (aus der CPE oder dem Katalog) steht direkt davor, nie bei KEV. „through X“ zählt nicht, es sagt nur, bis wohin eine Lücke bekannt ist. Gegenbeispiel: CVE-2024-5500 nennt „Google Updater prior to 1.3.36.351 in Google Chrome“; die Grenze gehört zum Updater, nicht zu Chrome. Hochgestuft wird nie.
   Führt die NVD das Produkt **ohne jede Versionsgrenze** (`mozilla:firefox:*`, formal „alle Versionen“, meist Altdaten aus der Zeit vor sauberen Versionsbereichen), gilt:
   - CVE jünger als 5 Jahre → `PossiblyAffected` mit Hinweis „Versionsbereich in der NVD nicht angegeben“ (Ampel: Gelb mit Hinweis)
   - älter → `Informational` mit Hinweis „Altdaten ohne Versionsangabe“, ohne Ampelwirkung (z. B. Firefox-CVEs von 2007)
   - trifft zusätzlich ein Eintrag mit Versionsgrenze zu, ist die CVE normal `Affected`
4. **KEV abgleichen:** CVEs im KEV-Katalog werden markiert.
5. **KEV ohne NVD-Versionsdaten:** Seit 2024 analysiert die NVD viele neue CVEs verzögert; solche CVEs findet die CPE-Suche nicht. KEV-Einträge, die laut Katalog (`Kev`) zum Produkt gehören, werden deshalb zusätzlich einzeln in der NVD nachgeschlagen:
   - NVD hat Versionsdaten und die Version ist betroffen → `Affected`
   - NVD hat Versionsdaten und die Version ist nicht betroffen → entfällt
   - keine Versionsdaten oder NVD nicht aktiviert → `PossiblyAffected` mit Hinweis „Version nicht prüfbar“ (in der Ampel: Gelb mit Hinweis)
6. **CIRCL** (wenn eingeschaltet): alle CVE-Datensätze zu Hersteller und Produkt der CPE, beim ersten Mal seitenweise, danach aus dem Bestand mit Nachladen der Änderungen (siehe Zwischenspeicher). Ausgewertet wird lokal, siehe [Versionsangaben bei CIRCL](#versionsangaben-bei-circl).
7. **Zusammenführen** je CVE-ID (siehe [Zwei Quellen](#zwei-quellen-nvd-und-circl)).
8. **EPSS** als eine Sammelabfrage für alle gefundenen CVEs.

## Versionsangaben bei CIRCL

CIRCL liefert die Datensätze des CVE-Programms im Format CVE 5. Ausgewertet werden die Einträge `affected` der CNA und der Ergänzung der CISA (ADP), die zum Produkt gehören: CPE der Ergänzung beginnt mit der CPE, oder der Produktname stimmt überein. Passt kein Eintrag, ist die CVE für dieses Produkt nicht auswertbar.

| Form | Beispiel | Bedeutung |
| --- | --- | --- |
| strukturiert | `version: 0, lessThan: 26.03` | < 26.03 (ebenso `lessThanOrEqual`, Untergrenze aus `version`) |
| einfacher Text | `< 8.9.6.1`, `<= 26.00`, `>= 9.11, < 26.01` | wie angegeben |
| „Fixed in X“, „before X“, „prior to X“ | `Fixed in 3.0.7` | < X |
| „X and earlier“ | `3.0.20 and earlier` | <= X |
| nur eine Version | `26.01` | gleiche Version betroffen, neuere nicht betroffen, ältere nicht auswertbar (oft ist nur die getestete Version genannt) |
| Commit-Kennung als Grenze | `version: 9a32b86…, lessThan: 8.0` | Grenze fällt weg (hier < 8.0, lieber ein Fehlalarm mehr); vermerkt in `logs\data-notes\<Datum>.jsonl` (Code `CommitVersionBound`) |
| anderes | `n/a`, `unspecified`, `versionType: git` | nicht auswertbar |

Nicht auswertbar gilt wie bei der NVD ohne Versionsgrenze: CVE jünger als 5 Jahre `PossiblyAffected` („Versionsbereich im CVE-Datensatz (CIRCL) nicht auswertbar“), älter `Informational`. Hat die NVD geprüft, entfallen alte CIRCL-Einträge ohne Versionsangabe ganz, weil die NVD zu ihnen entschieden hat.

## Zwei Quellen (NVD und CIRCL)

Gleiche CVE-ID heißt gleiche Lücke; sie erscheint einmal, auch wenn die Quellen sie verschieden bewerten. `Sources` nennt die Angabe jeder Quelle: `Affected`, `NotAffected`, `NotEvaluable` oder `Unknown` (in dieser Quelle nicht bekannt), dazu Bereich, Namensnennung und Link.

| NVD | CIRCL | Ergebnis |
| --- | --- | --- |
| betroffen | betroffen oder unbekannt | `Affected` |
| betroffen | nicht betroffen | `PossiblyAffected`, `SourcesDisagree` (Gelb, „Quellen widersprechen sich“) |
| nicht betroffen | betroffen | ebenso |
| nicht betroffen | nicht auswertbar | entfällt (die NVD hat Versionsdaten) |
| unbekannt | betroffen | `Affected` |
| unbekannt | nicht auswertbar (jung) | `PossiblyAffected` |

Ein Widerspruch widerlegt nie. Grün gibt es nur, wenn keine Quelle „betroffen“ meldet. Für CIRCL-Treffer, die die NVD-Suche nicht geliefert hat, fragt das Modul die NVD einmal je Produkt nach allen CVEs mit Daten zu diesem Produkt (`virtualMatchString` mit der CPE ohne Version, bis 2000 je Seite). Steht die CVE darin, gilt die Angabe der NVD für die installierte Version, sonst „in dieser Quelle nicht bekannt“. Einzelabrufe je CVE gibt es dafür nicht, sie wären ohne Schlüssel 6 Sekunden je CVE. Fällt eine Quelle aus, gilt das Programm als geprüft, solange die andere lief; der Ausfall steht in `Notes` und `ServiceProblems`. Grün gibt es dann aber nicht: Jede eingeschaltete Fundquelle muss mit Daten innerhalb des Höchstalters für Grün geliefert haben (`IncompleteSources`, Ampel siehe `BERICHT.md`).

## Plattformfilter

Unter derselben CPE führen die Quellen oft Lücken, die nur andere Betriebssysteme betreffen (z. B. Chrome oder Firefox für macOS, iOS oder Android). Sie zählen unter Windows nicht als Treffer. Ausgeschlossen wird nur, was eindeutig einer bekannten anderen Plattform zugeordnet ist: Android, iOS, iPadOS, macOS, Linux (auch Distributionen wie `ubuntu_linux`), ChromeOS. Alles Unbekannte zählt weiter (lieber ein Fehlalarm mehr).

- **NVD:** Ein Eintrag des Produkts zählt nicht, wenn sein `target_sw` eine andere Plattform nennt (`…:*:android:*:*`) oder seine Konfiguration UND-verknüpft ist und die Umgebung (Einträge mit `vulnerable: false`) nur aus Betriebssystemen anderer Plattformen besteht. Steht in der Umgebung Windows, eine Anwendung oder ein unbekanntes Betriebssystem, oder ist ein Knoten negiert, wird nicht gefiltert. Bleibt kein Eintrag übrig, meldet die NVD „nicht betroffen“ mit Hinweis `OtherPlatformOnly` (Args: Plattformen).
- **CIRCL (CVE 5):** Ein Eintrag in `affected` zählt nicht, wenn alle Angaben in `platforms` andere Plattformen sind („unknown“ oder „x64-based systems“ zählen als unbekannt), wenn alle passenden CPEs des Eintrags eine andere Plattform als `target_sw` nennen, oder wenn der Produktname sie in fester Form nennt („Firefox for Android“, „… on iOS“, „… for Mac“). Der Name zählt nur, wenn der Eintrag über einen ähnlichen Namen passt; bei genau gleichem Produkt (z. B. CPE `mozilla:firefox_for_android`) oder passender CPE im Eintrag schließt der Name nichts aus.
- **Widerspruch:** Meldet eine Quelle „nur andere Plattform“ und die andere „betroffen“, gilt wie bei Versionsdaten `PossiblyAffected` mit `SourcesDisagree` (Gelb).
- **KEV:** Ein KEV-Treffer ist widerlegt (`Refuted`, Hinweis `KevRefutedPlatform`), wenn alle Konfigurationen der NVD zum Produkt eindeutig nur andere Plattformen betreffen. Gilt eine Konfiguration auch für Windows oder ist sie unklar, bleibt der Treffer.
- **Anzeige:** Lücken, die laut den Quellen nur andere Plattformen betreffen und nicht trotzdem als Lücke zählen, stehen in `OtherPlatform` (je CVE `CveId`, `Platforms`, `Note` mit Code `OtherPlatformCve`), dazu `OtherPlatformNote` (`OtherPlatformHidden`, „2 Lücken betreffen nur andere Plattformen“). Sie wirken nicht auf die Ampel. Die App zeigt den Hinweis in den Details mit der Liste zum Aufklappen, der Bericht unter den Angaben zum Programm, der KI-Berater bekommt sie als `otherPlatform`.

## Ergebnis (`SoftwareInventory.VulnerabilityStatus`)

| Feld | Bedeutung |
| --- | --- |
| `Name`, `Version`, `CatalogId`, `Record` | geprüftes Programm |
| `CpeSource` | `Catalog` oder `User` (bestätigte Zuordnung) |
| `Cpe` | abgefragte CPE-Namen mit Version |
| `Status` | `Checked` (NVD oder CIRCL abgefragt) oder `Unknown` |
| `Reason` | bei `Unknown` immer gesetzt, als Meldung mit Code: `ServiceDisabled` („Dienst NVD nicht aktiviert“), `NoCpe`, `VersionUnreadable`, `RateLimit`, `ServiceUnavailable` … |
| `Notes` | Hinweise als Meldungen, z. B. `ServiceDisabled` mit Args `KEV` |
| `Vulnerabilities` | Liste, KEV zuerst, dann nach CVSS absteigend; Hinweise (`Informational`) am Ende |
| `Refuted` | KEV-Treffer, die für diese Version widerlegt sind (NVD-Versionsdaten, Plattform oder Katalog) |
| `OtherPlatform`, `OtherPlatformNote` | Lücken nur für andere Plattformen, ohne Ampelwirkung (siehe Plattformfilter) |

Je Schwachstelle (`SoftwareInventory.Vulnerability`): `CveId`, `Assessment` (`Affected`, `PossiblyAffected` oder `Informational`), `Note` (Meldung, z. B. `KevNvdNoVersionData`), `Sources` (Angabe je Quelle: `Source`, `Verdict`, `Range`, `Note`, `OtherPlatform`, `Attribution`, `Url`), `SourcesDisagree`, `Score`, `Severity`, `CvssVersion` (höchste vorhandene: 4.0 vor 3.1, 3.0, 2.0; bevorzugt die Bewertung der NVD, sonst aus dem CVE-Datensatz), `Published`, `Description` (englisch, gekürzt), `Kev`, `KevDateAdded`, `KevRansomware`, `Epss`, `EpssPercentile`, `Url`.

## CPE für Programme ohne Katalogeintrag

```powershell
$gimp = Get-SoftwareInventory | Where-Object Name -like 'GIMP*'
$gimp | Find-CpeCandidate                                  # Vorschläge aus dem NVD-Wörterbuch, unbestätigt
$gimp | Set-CpeMapping -Cpe 'cpe:2.3:a:gimp:gimp'          # Zuordnung bestätigen
Get-CpeMapping                                             # bestätigte Zuordnungen anzeigen
Get-CpeMapping | Where-Object Name -like 'GIMP*' | Remove-CpeMapping
```

`Find-CpeCandidate` sucht den Programmnamen ohne Version, Architektur und Zusätze in Klammern im CPE-Wörterbuch (Dienst `NVD`, Ergebnis 7 Tage zwischengespeichert). Passt dabei kein Produkt genau, sucht es mit dem Produktteil der winget-ID weiter („Ghisler.TotalCommander“ → „Total Commander“). Bewertet wird, wie gut Produkt und Hersteller passen (Herstelleraliase in `Data/cpe-vendor-alias.json`); veraltete CPEs und Treffer ohne Bezug zum Produkt entfallen. Vorschläge werden nie automatisch verwendet. In der App geht das über „CPE zuordnen“ in den Details; dort lässt sich eine eigene Zuordnung auch wieder entfernen und mit „Vorschlag melden“ für den Katalog vorschlagen (`Get-CpeMappingReport`). Bestätigte Zuordnungen liegen unter `%APPDATA%\SoftwareInventory\cpe-map.json` (Schlüssel: winget-ID, sonst Name ohne Version und Hersteller). Ein Katalogeintrag mit CPE hat Vorrang.

## Grenzen

- Geprüft werden nur Programme mit Katalogeintrag oder bestätigter CPE-Zuordnung.
- CVEs ohne CPE-Konfiguration in der NVD werden nur über KEV erfasst, nicht über die CPE-Suche.
- Verglichen wird die Versionsnummer; Zusatzfelder einer CPE (z. B. `3.15.0:alpha1`, Ausgabe `esr`) werden nicht ausgewertet. Im Zweifel entsteht ein Fehlalarm, kein übersehener Treffer.
- OSV und GitHub Security Advisories sind noch nicht angebunden.
