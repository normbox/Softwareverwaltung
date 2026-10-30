# Externe Dienste: was wohin geht

Stand: 28.10.2026

Das Inventar selbst entsteht vollständig auf dem eigenen Rechner. Erst für den Versions- und Sicherheitsabgleich und für den KI-Berater spricht die App mit Diensten im Internet bzw. im eigenen Netz. Dieses Dokument zeigt für jeden Dienst, welche Daten übertragen werden, wer sie bekommt und was man vor der Nutzung beachten sollte.

> **Keine Rechtsberatung.** Die Angaben zu Bedingungen der Anbieter geben den recherchierten Stand wieder. Anbieter ändern ihre Bedingungen; vor dem Einsatz, besonders in Firmen, die aktuelle Fassung lesen.

## Grundsätze

1. **Alles Externe ist aus, bis es eingeschaltet wird.** Jeder Dienst lässt sich in den Einstellungen einzeln ein- und ausschalten. Ohne Netzwerk funktioniert das Inventar weiterhin.
2. **Sparsam fragen.** Wo ein Dienst eine Gesamtliste anbietet (CISA KEV), lädt die App die ganze Liste und vergleicht lokal. Dann erfährt der Anbieter nicht, welche Programme installiert sind. Wo das nicht geht (NVD, CIRCL, EPSS, GitHub), fragt die App gezielt und nur mit den nötigen Angaben.
3. **Zwischenspeicher.** Antworten werden zwischengespeichert, die Haltbarkeit ist je Quelle einstellbar (Standard: neueste Version 6 Stunden, NVD, CIRCL, EPSS und KEV je 24 Stunden). Ist ein Dienst nicht erreichbar, gelten ältere Ergebnisse weiter und sind als veraltet gekennzeichnet.
4. **Eigene Schlüssel.** Das Projekt betreibt keinen eigenen Server und hat keinen Zugang zu den Daten der Nutzer. API-Schlüssel gehören dem Nutzer und liegen in der Windows-Anmeldeinformationsverwaltung.
5. **Jeder Abruf überträgt die IP-Adresse** des Rechners (bzw. des Firmen-Proxys) und technische Daten wie Uhrzeit und Programmkennung (User-Agent `SoftwareInventory/<Version>`). Das gilt für alle folgenden Dienste und wird nicht jedes Mal wiederholt.

## Dienste einrichten: alles manuell, für alle gleich

Die App schaltet keinen externen Dienst selbst ein und unterscheidet nicht zwischen Privat- und Firmennutzung. Jeder Dienst wird vom Nutzer bzw. Administrator bewusst eingerichtet, auf dieselbe Weise für alle.

- **Standard:** Alle Dienste sind nach der Installation aus.
- **Erster Start:** Die App fragt einmal „Privat“ oder „Firma“ und zeigt die passenden Hinweise zu den Nutzungsbedingungen der Dienste. Die Angabe schaltet nichts ein.
- **Einstellungen:** Jeder Dienst hat einen eigenen Schalter mit dem Hinweis, was übertragen wird. Vorlagen („Schnell“, „Gründlich“) setzen nur sichtbare Häkchen, nie Dienste; übernommen wird erst mit „Speichern“.
- **Bedingungen sichtbar machen statt entscheiden:** Die App zeigt zu jedem Dienst an, welche Nutzung der Anbieter erlaubt, was übertragen wird und wohin. Die App kann nicht prüfen, ob die eigene Nutzung den Bedingungen entspricht; die Verantwortung liegt beim Nutzer.
- **Ohne Dienst weiter:** Ist ein Dienst nicht eingeschaltet, läuft die App ohne ihn und nennt den Grund, z. B. „Nicht auf Lücken geprüft: Dienst NVD nicht aktiviert“.
- **Für Firmen (geplant, Etappe 6):** Ein Administrator soll Einstellungen vorab festlegen und sperren können, über eine Richtlinie in der Registry (Vorschlag: `HKLM\SOFTWARE\Policies\Softwareverwaltung`). Die Richtlinie automatisiert nichts, sie übernimmt nur die Einstellungen, die der Administrator selbst gewählt hat.

## Hinweise je Dienst: wie sie gepflegt werden

Die Hinweise zu den Nutzungsbedingungen stehen im Modul (`Get-ServiceTermsNotice`) mit Dienst, Name, Kurzfassung der Bedingungen, einem zusätzlichen Hinweis für Firmen und dem Link zu den Originalbedingungen. Die Texte liegen in `SoftwareInventory.Strings.psd1`.

Für weitere Anbieter ist ein ausführlicherer Dienstkatalog vorgesehen:

| Feld | Bedeutung | Beispiel |
| --- | --- | --- |
| `Id`, `Name`, `Operator`, `Country` | Kennung, Anzeigename, Betreiber, Sitz | `nvd`, NVD, NIST, USA |
| `Category` | Versionen, Schwachstellen, KI, Reputation, Recherche | Schwachstellen |
| `UsageClass` | Hinweis auf die Nutzungsbedingungen: `A` frei für alle, `B` kostenlos nur privat, `C` eigenes Konto/Vertrag | `A` |
| `UsageNote` | Bedingungen in einem Satz, wird beim Einschalten angezeigt | „Kostenlos, auch kommerziell; Hinweis auf die NVD“ |
| `SendsInventoryData` | überträgt der Dienst Programmnamen, Versionen, Hashes? | ja (CPE mit Version) |
| `DataSent` | Klartext für die Einstellungen | „Hersteller, Produkt und Version (CPE)“ |
| `RequiresKey` | Schlüssel nötig? | nein (optional) |
| `TermsUrl`, `TermsCheckedOn` | Bedingungen und Datum der letzten Prüfung | Link, 2026-10-26 |

Regeln für Beiträge: Ein neuer Dienst braucht einen Hinweis zu den Bedingungen, einen Link auf die geprüften Bedingungen und einen Abschnitt in diesem Dokument. Er ist immer standardmäßig aus. Im Zweifel wird er als Klasse B eingestuft.

## Was die KI sehen darf: Freigabestufen

Geplant für Etappe 4b. Bis dahin geben die Werkzeuge des Beraters gar keine Nutzungsspuren weiter; ein Test sichert das ab.

Unabhängig vom Anbieter lässt sich festlegen, wie tief der KI-Berater in die Daten schauen darf. Die Grenze setzt das Modul selbst: Die Werkzeuge (`get_inventory` usw.) geben nur die Felder der eingestellten Stufe zurück. Was nicht freigegeben ist, erreicht das Modell gar nicht; eine Anweisung im Prompt allein würde nicht genügen.

| Stufe | Die KI sieht | Die KI sieht nicht |
| --- | --- | --- |
| **0 Übersicht** | Anzahl Programme, Anzahl Updates, Ampelverteilung, CVE-Nummern ohne Programmzuordnung | Programmnamen |
| **1 Programmliste** | Name, Hersteller, installierte und neueste Version, Ampel, CVEs, KEV/EPSS | Pfade, Installationsdetails, portable Programme |
| **2 Installationsdetails** | zusätzlich Installationsart, Bereich (Rechner/Benutzer), winget-ID, bereinigte Pfade | portable Programme, Nutzungsspuren |
| **3 Portable Programme** | zusätzlich gefundene portable Programme mit Version, Signaturstatus und Fundort-Art (z. B. „Downloads“) | Nutzungsspuren |
| **4 Nutzungsspuren, vergröbert** | zusätzlich „zuletzt genutzt“ in groben Klassen (unter 1 Monat, 1 bis 6 Monate, länger, nie) und „läuft im Autostart“ | genaue Zeitstempel, Startzähler, Benutzerzuordnung |

Genaue Zeitstempel, Startzähler und die Zuordnung zu einzelnen Benutzern gibt es für keine KI, auch nicht lokal.

Weitere Einschränkungen:

- **Vorerst nur lokale Anbieter**, Voreinstellung Stufe 3, mit einer Vorschau der übertragenen Daten. Für spätere externe Anbieter gelten eigene Stufen (Vorschlag: höchstens Stufe 1).
- **Ausschlussliste (geplant):** Einzelne Programme, Hersteller oder Ordner lassen sich ganz vor der KI verbergen (z. B. interne Firmenprogramme).
- **Firmen (geplant):** Ein Administrator kann per Richtlinie die höchste erlaubte Stufe je Anbieter festlegen; Nutzer können sie dann nur senken.
- Die Bereinigung von Benutzer- und Rechnernamen gilt zusätzlich auf jeder Stufe.

## Übersicht

Klassen: **A** frei für alle · **B** kostenlos nur privat · **C** eigenes Konto/Vertrag.

| Dienst | Betreiber, Sitz | Übertragene Inhalte | Klasse | Status | Standard |
| --- | --- | --- | --- | --- | --- |
| winget-Paketliste | Microsoft, USA | Abfrage der Paketkataloge durch winget | A | vorhanden | aus |
| winget-Suche nach neuen Versionen | Microsoft, USA | Paket-IDs oder Programmnamen an die Quelle `winget` | A | vorhanden | aus |
| Updates und Deinstallation über winget | Microsoft bzw. Hersteller | Paket-ID; Download des Installationsprogramms | A | vorhanden | nur nach Bestätigung |
| GitHub Releases | GitHub (Microsoft), USA | Name des Repositorys aus dem Katalog | A (Token optional) | vorhanden | aus |
| NVD CVE- und CPE-API | NIST, USA | Produktkennung (CPE) mit Version; bei CPE-Vorschlägen der Programmname | A (Schlüssel optional) | vorhanden | aus |
| CIRCL Vulnerability-Lookup | CIRCL, Luxemburg | Hersteller und Produkt aus der CPE, ohne Version | A (Schlüssel optional) | vorhanden | aus |
| CISA KEV | CISA, USA | nichts außer dem Abruf der Gesamtliste | A | vorhanden | aus |
| EPSS | FIRST.org, USA | Nummern der gefundenen Lücken (CVE-IDs) | A | vorhanden | aus |
| Lokaler KI-Server (Ollama, LM Studio, Unsloth Studio) | eigener Rechner | nichts verlässt den Rechner | A (Modelllizenz beachten) | geplant (4b) | aus |
| KI-Server unter eigener Adresse | eigener Server | bereinigte Unterhaltung und Werkzeugergebnisse an diesen Server | A | geplant (4b) | aus |

Klasse und Hinweis geben den Stand der Prüfung vom 24. bis 26.10.2026 wieder.

## Die Dienste im Einzelnen

### winget (Microsoft)

- **Was:** Beim Lesen der Paketliste aktualisiert winget seine Quellen (Download der Kataloge). Die winget-Suche fragt die Quelle `winget` nach Programmen ohne winget-ID. Bei Update oder Deinstallation lädt winget das Installationsprogramm vom Hersteller oder aus dem Store.
- **Beachten:** Die Quelle `msstore` hat eine eigene Vereinbarung. Die App zeigt sie vor der ersten Aktion an einem Store-Paket einmal an (Standard „Abbrechen“) und speichert die Zustimmung; erst dann enthält der Befehl `--accept-source-agreements`. Dabei geht unter anderem der Ländercode des Rechners an Microsoft. winget sendet Telemetrie gemäß den Windows-Diagnoseeinstellungen; abschaltbar in `winget settings`.
- **Firmen:** winget lässt sich per Gruppenrichtlinie steuern (erlaubte Quellen, eigene REST-Quelle).

### GitHub Releases

- **Was:** Für Programme mit bekanntem GitHub-Repository (aus dem Katalog) fragt die App die neueste Veröffentlichung ab.
- **Grenzen:** ohne Token 60 Anfragen pro Stunde und IP, mit Token 5.000. Hinter einem gemeinsamen Firmen-Proxy ist die Grenze ohne Token schnell erreicht; die App bricht weitere GitHub-Abfragen im selben Lauf dann ab.
- **Token:** Ein „fine-grained“ Token **ohne jede Berechtigung** genügt für öffentliche Repositorys. Keine Tokens mit Schreibrechten verwenden.

### NVD (National Vulnerability Database)

- **Was:** CVEs und Schweregrade (CVSS) zu Produkten, abgefragt über die zugeordnete CPE mit Version. Außerdem Vorschläge für CPE-Zuordnungen aus dem CPE-Wörterbuch („CPE zuordnen“ in den Details): Suchbegriff ist der Programmname ohne Version, Architektur und Zusätze, falls nötig zusätzlich der Produktteil der winget-ID (z. B. „Total Commander“).
- **Bedingungen:** Pflichthinweis „This product uses the NVD API but is not endorsed or certified by the NVD.“. Schlüssel sind persönlich und dürfen nicht weitergegeben oder ins Repository gelegt werden. Ohne Schlüssel gelten engere Abfragegrenzen; die App wartet dann 6 Sekunden zwischen zwei Anfragen, mit Schlüssel 0,6 Sekunden.
- **Datenschutz:** Abfragen nach Produkt und Version verraten, welche Software installiert ist. Ein datensparsamerer Gesamtabgleich (Synchronisierung des NVD-Bestands über Änderungszeiträume, lokaler Vergleich) ist nicht umgesetzt.

### CIRCL Vulnerability-Lookup

- **Was:** Zweite Quelle für Schwachstellen neben der NVD, einzeln schaltbar. Abgefragt wird `/api/vulnerability/search/{hersteller}/{produkt}` mit Hersteller und Produkt aus der zugeordneten CPE. CIRCL liefert die CVE-Datensätze des CVE-Programms (Format CVE 5, mit Ergänzungen der CISA); die App wertet die Versionsangaben auf dem eigenen Rechner aus. Was sich nicht auswerten lässt, gilt wie bei der NVD ohne Versionsdaten: jünger als 5 Jahre „möglicherweise betroffen“, älter nur als Hinweis.
- **Zusammenführung:** Gleiche CVE-ID heißt gleiche Lücke, sie wird nur einmal gezählt. Die Details zeigen die Angabe jeder Quelle einzeln. Meldet eine Quelle „betroffen“ und die andere mit Versionsdaten „nicht betroffen“, gilt „möglicherweise betroffen“ mit dem Grund „Quellen widersprechen sich“ (Gelb), nicht widerlegt. Fehlt zu CIRCL-Treffern die NVD-Angabe, fragt die App die NVD einmal je Produkt nach allen CVEs mit Daten zu diesem Produkt (nur wenn die NVD eingeschaltet ist); dabei geht die CPE ohne Version an die NVD.
- **Bedingungen:** Kostenlos. Ohne Schlüssel 20 Anfragen pro Minute (die App wartet 3 Sekunden), mit Schlüssel aus einem Benutzerkonto bei CIRCL 40 (1,5 Sekunden). Die App nennt sich im User-Agent mit der Projektadresse und spiegelt den Bestand nicht. Die CVE-Datensätze stehen unter CC BY 4.0; die App nennt die Quelle bei jedem Treffer und im Bericht. Details in [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).
- **Datenschutz:** Datensparsamer als die NVD-Abfrage, weil keine Version gesendet wird; CIRCL erfährt trotzdem, nach welchen Produkten gefragt wird. Sitz in Luxemburg (EU).
- **Zugriffsregeln:** [Access patterns for automated consumers](https://www.vulnerability-lookup.org/documentation/access-patterns.html) und maschinenlesbar [api-policy.json](https://vulnerability.circl.lu/.well-known/api-policy.json) (geprüft am 29.10.2026, Policy-Version 1): eigener User-Agent mit Kontakt, Abfragegrenzen einhalten, bei 429 `Retry-After` beachten, nicht spiegeln oder über CVE-Nummern iterieren, für Aktualisierungen `since=` statt erneutem Vollabruf. Bei Änderungen der Policy-Version die Umsetzung erneut prüfen. Umsetzung: ein Bestand je Produkt, danach nur `since=` (filtert nach `dateUpdated`, geprüft am 30.10.2026); vollständig nur ohne Bestand, nach 30 Tagen oder bei „Neu prüfen ohne Cache“.

### CISA KEV und EPSS

- **Was:** Liste aktiv ausgenutzter Lücken (KEV) und Ausnutzungswahrscheinlichkeit (EPSS).
- **Datenschutz:** KEV wird als Gesamtliste geladen; es fließen keine Inventardaten ab. EPSS erhält die Nummern der gefundenen Lücken (CVE-IDs), nicht die Programmnamen.
- **Bedingungen:** KEV ist gemeinfrei (CC0), Logo und Siegel der CISA dürfen nicht verwendet werden. EPSS ist frei nutzbar; Quellenangabe in der App.

### Lokale KI (Ollama, LM Studio, Unsloth Studio) – geplant für Etappe 4b

- **Was:** Das Modell läuft auf dem eigenen Rechner; nichts verlässt ihn. Datenschutzrechtlich die einfachste Wahl. Angesprochen wird jeder Server mit OpenAI-kompatibler Schnittstelle und Tool-Unterstützung.
- **Bereinigung:** Benutzername, Rechnername und Benutzerpfade werden auch für lokale Modelle ersetzt.
- **Beachten:** Ollama lauscht standardmäßig nur auf `localhost`. Wer es im Netzwerk freigibt (`OLLAMA_HOST=0.0.0.0`), sollte den Zugriff per Firewall beschränken, da Ollama keine Anmeldung kennt. Läuft der Server im Firmennetz, gehen die Daten dorthin; dann gilt dasselbe wie für jeden internen Dienst. Unsloth Studio verlangt einen API-Schlüssel.
- **Lizenzen:** Jedes Modell hat eine eigene Lizenz. Für Firmen eignen sich Modelle unter Apache-2.0 oder MIT am einfachsten; bei Llama und Gemma die jeweiligen Bedingungen lesen.
- **Qualität:** Kleine lokale Modelle beherrschen Tool-Aufrufe unterschiedlich gut. Es gibt kein Standardmodell; gewählt wird aus den installierten Modellen.

## Geplant oder nur als Idee (nicht umgesetzt)

Diese Dienste sind nicht eingebaut. Die Notizen bleiben für die spätere Umsetzung stehen.

### Claude API und andere Cloud-KI (später als Erweiterung)

- Der KI-Berater würde die Unterhaltung und die Ergebnisse der Werkzeugaufrufe an das Modell schicken, bereinigt und im Umfang der Freigabestufe (Vorschlag für extern: Stufe 1).
- Die Bereinigung ist eine **Pseudonymisierung, keine Anonymisierung**: Eine Liste installierter Software kann einen Rechner trotzdem kennzeichnen.
- Bedingungen (Stand Oktober 2026, vor Nutzung prüfen): Die API fällt unter die Commercial Terms von Anthropic, auch bei privater Nutzung. Laut Anthropic werden API-Eingaben nicht zum Training verwendet und standardmäßig nach 30 Tagen gelöscht. Die Verarbeitung erfolgt in den USA.

### Web-Recherche des Beraters (später)

Für unbekannte Programme könnte der Berater im Web suchen; Ergebnisse gälten als „unbestätigt“. Suchbegriffe enthielten meist Programmnamen.

### OSV.dev und GitHub Advisory Database (Idee)

Schwachstellen in Open-Source-Paketen. Abfragen enthielten Paketname und Version; Daten stehen unter der Lizenz ihrer Ursprungsdatenbank (GitHub Advisory Database: CC BY 4.0).

### VirusTotal (Idee)

- Abgleich des SHA256-Hashs einer unbekannten Datei, **niemals die Datei selbst**.
- Die öffentliche (kostenlose) API **darf nicht in kommerziellen Produkten oder geschäftlichen Abläufen** verwendet werden und ist auf 4 Anfragen pro Minute und 500 pro Tag begrenzt (Klasse B).

### Installierter Virenschutz (Idee)

- Bitdefender für Privatkunden hat nach unserer Recherche keine öffentliche Schnittstelle.
- Herstellerunabhängig ginge über Windows: der Status aus dem Windows-Sicherheitscenter (WMI `root\SecurityCenter2`, Klasse `AntiVirusProduct`) als Punkt für die Ampel, und die Prüfung einer Datei über AMSI. Microsoft Defender bietet zusätzlich `Get-MpComputerStatus` und `Get-MpThreat`.
- Business-Produkte (z. B. Bitdefender GravityZone, Microsoft Defender for Endpoint) haben echte Schnittstellen (Klasse C).

### EUVD der ENISA (zurückgestellt)

Nutzungsbedingungen, Datenlizenz und Abfragegrenzen der API waren am 28.10.2026 nicht auffindbar; die API antwortete schnell mit HTTP 429. Erneut prüfen, wenn es Neuigkeiten gibt.

## Empfehlungen für Nutzer

| Situation | Empfehlung |
| --- | --- |
| Privat, maximaler Datenschutz | KEV an; NVD und EPSS nur bei Bedarf; KI-Berater mit Modell auf dem eigenen Rechner |
| Privat, gründliche Prüfung | NVD (mit kostenlosem Schlüssel), KEV, EPSS, GitHub und winget-Suche an |
| Firma | Vorher [FIRMENEINSATZ.md](FIRMENEINSATZ.md) durcharbeiten; Dienste einzeln bewerten |
| Ohne Internet | Nur Inventar; Ergebnisse aus dem Zwischenspeicher sind als veraltet gekennzeichnet; Abgleich später nachholen |
