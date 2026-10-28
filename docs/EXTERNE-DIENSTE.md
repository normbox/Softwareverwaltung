# Externe Dienste: was wohin geht

Stand: 24.10.2026

Das Inventar selbst entsteht vollständig auf dem eigenen Rechner. Erst für den Versions- und Sicherheitsabgleich und für den KI-Berater spricht die App mit Diensten im Internet. Dieses Dokument zeigt für jeden Dienst, welche Daten übertragen werden, wer sie bekommt und was man vor der Nutzung beachten sollte.

> **Keine Rechtsberatung.** Die Angaben zu Bedingungen der Anbieter geben den recherchierten Stand wieder. Anbieter ändern ihre Bedingungen; vor dem Einsatz, besonders in Firmen, die aktuelle Fassung lesen.

## Grundsätze

1. **Alles Externe ist abschaltbar.** Jeder Dienst lässt sich in den Einstellungen einzeln aus- und einschalten. Ohne Netzwerk funktioniert das Inventar weiterhin.
2. **Sparsam fragen.** Wo ein Dienst eine Gesamtliste anbietet (CISA KEV, EPSS, NVD-Datenbestand), lädt die App die ganze Liste und vergleicht lokal. Dann erfährt der Anbieter nicht, welche Programme installiert sind.
3. **Eigene Schlüssel.** Das Projekt betreibt keinen eigenen Server und hat keinen Zugang zu den Daten der Nutzer. API-Schlüssel gehören dem Nutzer und liegen in der Windows-Anmeldeinformationsverwaltung.
4. **Transparenz.** Die Einstellungen zeigen vor dem ersten Senden an eine Cloud-KI eine Vorschau der zu übertragenden Daten.
5. **Jeder Abruf überträgt die IP-Adresse** des Rechners (bzw. des Firmen-Proxys) und technische Daten wie Uhrzeit und Programmkennung (User-Agent). Das gilt für alle folgenden Dienste und wird nicht jedes Mal wiederholt.

## Dienste einrichten: alles manuell, für alle gleich

Die App schaltet keinen externen Dienst selbst ein und unterscheidet nicht zwischen Privat- und Firmennutzung. Jeder Dienst wird vom Nutzer bzw. Administrator bewusst eingerichtet, auf dieselbe Weise für alle.

- **Standard:** Alle Dienste sind nach der Installation aus. Ein Einrichtungsassistent beim ersten Start stellt sie vor und lässt jeden einzeln einschalten; überspringen ist möglich.
- **Pro Dienst:** einschalten, ggf. eigenen Schlüssel eintragen, Freigabestufe wählen (bei KI), Bedingungen bestätigen.
- **Bedingungen sichtbar machen statt entscheiden:** Die App zeigt zu jedem Dienst aus dem Dienstkatalog an, welche Nutzung der Anbieter erlaubt (z. B. „Kostenlose API nur für private, nicht-kommerzielle Nutzung“), was übertragen wird und wohin. Der Nutzer bestätigt beim Einschalten, dass seine Nutzung den Bedingungen entspricht. Die App kann das nicht prüfen; die Verantwortung liegt beim Nutzer.
- **Ohne Dienst weiter:** Ist ein Dienst nicht eingerichtet, läuft die App ohne ihn und zeigt an, welche Prüfung dadurch fehlt (z. B. „Hash-Abgleich nicht aktiv“).
- **Optional für Firmen:** Ein Administrator kann Einstellungen vorab festlegen und sperren, über eine Richtlinie in der Registry (Vorschlag: `HKLM\SOFTWARE\Policies\Softwareverwaltung`). Ohne Richtlinie ist alles frei einstellbar. Die Richtlinie automatisiert nichts, sie übernimmt nur die Einstellungen, die der Administrator selbst gewählt hat.

## Dienstkatalog: neue Anbieter aufnehmen

Damit weitere Anbieter (andere KI-Dienste, Schwachstellen- oder Versionsquellen, Virenscanner) ohne Sonderlogik dazukommen, beschreibt ein Eintrag im Dienstkatalog jeden Dienst. Die App zeigt daraus die Hinweise beim Einrichten an.

| Feld | Bedeutung | Beispiel VirusTotal |
| --- | --- | --- |
| `Id`, `Name`, `Operator`, `Country` | Kennung, Anzeigename, Betreiber, Sitz | `virustotal`, VirusTotal, Google, USA |
| `Category` | Versionen, Schwachstellen, KI, Reputation, Recherche | Reputation |
| `UsageClass` | Hinweis auf die Nutzungsbedingungen: `A` frei für alle, `B` kostenlos nur privat, `C` eigenes Konto/Vertrag | `B` |
| `UsageNote` | Bedingungen in einem Satz, wird beim Einschalten angezeigt | „Kostenlose API nur privat; geschäftlich Premium nötig“ |
| `SendsInventoryData` | überträgt der Dienst Programmnamen, Versionen, Hashes? | ja (Hashes) |
| `DataSent` | Klartext für die Einstellungen | „SHA256-Hash der Datei“ |
| `RequiresKey` | Schlüssel nötig? | ja |
| `TermsUrl`, `TermsCheckedOn` | Bedingungen und Datum der letzten Prüfung | Link, 2026-10-24 |

Regeln für Beiträge: Ein neuer Dienst braucht einen vollständigen Eintrag, einen Link auf die geprüften Bedingungen und einen Abschnitt in diesem Dokument. Er ist immer standardmäßig aus. Im Zweifel wird er als Klasse B eingestuft. Ändert ein Anbieter seine Bedingungen, wird `TermsCheckedOn` aktualisiert und die Klasse neu bewertet.

## Was die KI sehen darf: Freigabestufen

Unabhängig vom Anbieter lässt sich festlegen, wie tief der KI-Berater in die Daten schauen darf. Die Grenze setzt das Modul selbst: Die Werkzeuge (`get_inventory` usw.) geben nur die Felder der eingestellten Stufe zurück. Was nicht freigegeben ist, erreicht das Modell gar nicht; eine Anweisung im Prompt allein würde nicht genügen.

| Stufe | Die KI sieht | Die KI sieht nicht |
| --- | --- | --- |
| **0 Übersicht** | Anzahl Programme, Anzahl Updates, Ampelverteilung, CVE-Nummern ohne Programmzuordnung | Programmnamen |
| **1 Programmliste** | Name, Hersteller, installierte und neueste Version, Ampel, CVEs, KEV/EPSS | Pfade, Installationsdetails, portable Programme |
| **2 Installationsdetails** | zusätzlich Installationsart, Bereich (Rechner/Benutzer), winget-ID, bereinigte Pfade | portable Programme, Nutzungsspuren |
| **3 Portable Programme** | zusätzlich gefundene portable Programme mit Version, Signaturstatus und Fundort-Art (z. B. „Downloads“) | Nutzungsspuren |
| **4 Nutzungsspuren, vergröbert** | zusätzlich „zuletzt genutzt“ in groben Klassen (unter 1 Monat, 1 bis 6 Monate, länger, nie) und „läuft im Autostart“ | genaue Zeitstempel, Startzähler, Benutzerzuordnung |

Genaue Zeitstempel, Startzähler und die Zuordnung zu einzelnen Benutzern gibt es für keine KI, auch nicht lokal. Für die Beratung („Das Programm haben Sie seit Monaten nicht genutzt, deinstallieren?“) reichen die groben Klassen.

Weitere Einschränkungen:

- **Getrennt nach Anbieter:** Für lokale und externe KI gelten eigene Stufen. Voreinstellung: lokal Stufe 3, extern Stufe 1.
- **Ausschlussliste:** Einzelne Programme, Hersteller oder Ordner lassen sich ganz vor der KI verbergen (z. B. interne Firmenprogramme). Sie erscheinen dann weder in Listen noch in Suchanfragen.
- **Tiefenscan ohne KI:** Die Nutzungsspuren können für die eigene Ansicht gelesen werden, ohne sie der KI freizugeben.
- **Firmen (optional):** Ein Administrator kann per Richtlinie die höchste erlaubte Stufe je Anbieter festlegen; Nutzer können sie dann nur senken. Empfehlung: extern höchstens Stufe 1, Stufe 4 nur mit Betriebsvereinbarung.
- **Vorschau:** Die Einstellungen zeigen für jede Stufe ein Beispiel der Daten, die tatsächlich übertragen würden.
- Die Bereinigung von Benutzer- und Rechnernamen gilt zusätzlich auf jeder Stufe.

## Übersicht

Klassen: **A** frei für alle · **B** kostenlos nur privat · **C** eigenes Konto/Vertrag.

| Dienst | Betreiber, Sitz | Übertragene Inhalte | Klasse | Standard |
| --- | --- | --- | --- | --- |
| winget-Quellen | Microsoft, USA | Abfrage der Paketkataloge; bei Aktionen die Paket-ID | A | an (Teil des Inventars), abschaltbar |
| GitHub Releases | GitHub (Microsoft), USA | Name des abgefragten Repositorys (z. B. `notepad-plus-plus/notepad-plus-plus`) | A (Token optional) | aus |
| NVD CVE-API | NIST, USA | Produktkennung (CPE) bzw. Änderungszeitraum, je nach Abfrageart | A (Schlüssel optional) | aus |
| CISA KEV | CISA, USA | nichts außer dem Abruf der Gesamtliste | A | aus |
| EPSS | FIRST.org, USA | Gesamtliste oder CVE-Nummern | A | aus |
| OSV.dev | Google, USA | Paketname und Version | A | aus |
| Claude API | Anthropic, USA | Chat-Text und Werkzeugergebnisse (Programmliste, Versionen, CVEs), bereinigt | C | aus |
| Ollama / LM Studio lokal | eigener Rechner | nichts verlässt den Rechner | A (Modelllizenz beachten) | aus |
| Ollama auf eigenem Server | eigener Server | wie Claude API, aber zum eigenen Server | A | aus |
| Web-Recherche des Beraters | abhängig von der Umsetzung (z. B. Suchwerkzeug der Claude API) | Suchbegriffe, meist Programmnamen | je nach Anbieter | aus |
| VirusTotal | Google, USA | SHA256-Hash einer Datei, **niemals die Datei selbst** | B | aus |
| Installierter Virenschutz (Bitdefender, Defender u. a.) | eigener Rechner | Datei wird lokal vom Virenscanner geprüft; ob dieser selbst etwas an seine Cloud meldet, bestimmt seine eigene Einstellung | A (Bedingungen des Virenschutzes) | aus |
| Firmen-Virenschutz mit API (z. B. Bitdefender GravityZone, Microsoft Defender for Endpoint) | Hersteller bzw. eigene Konsole | Abfrage von Status und Funden je Rechner | C | aus |

Klasse und Hinweis geben den Stand der Prüfung am 24.10.2026 wieder.

## Die Dienste im Einzelnen

### winget (Microsoft)

- **Was:** Beim Lesen der Paketliste aktualisiert winget seine Quellen (Download der Kataloge). Bei Update oder Deinstallation lädt winget das Installationsprogramm vom Hersteller oder aus dem Store.
- **Beachten:** Die Quelle `msstore` hat eine eigene Vereinbarung, der der Nutzer einmal zustimmen muss. Die App übergeht das nicht stillschweigend. winget sendet Telemetrie gemäß den Windows-Diagnoseeinstellungen; abschaltbar in `winget settings`.
- **Firmen:** winget lässt sich per Gruppenrichtlinie steuern (erlaubte Quellen, eigene REST-Quelle).

### GitHub Releases

- **Was:** Für Programme mit bekanntem GitHub-Repository fragt die App die neueste Veröffentlichung ab.
- **Grenzen:** ohne Token 60 Anfragen pro Stunde und IP, mit Token 5.000. Hinter einem gemeinsamen Firmen-Proxy ist die Grenze ohne Token schnell erreicht.
- **Token:** Ein „fine-grained“ Token **ohne jede Berechtigung** genügt für öffentliche Repositorys. Keine Tokens mit Schreibrechten verwenden.

### NVD (National Vulnerability Database)

- **Was:** CVEs und Schweregrade (CVSS) zu Produkten.
- **Bedingungen:** Pflichthinweis „This product uses the NVD API but is not endorsed or certified by the NVD.“ (in der App unter „Über“). Schlüssel sind persönlich und dürfen nicht weitergegeben oder ins Repository gelegt werden. Ohne Schlüssel gelten deutlich engere Abfragegrenzen; die App wartet zwischen Anfragen entsprechend.
- **Datenschutz:** Abfragen nach Produkt verraten, welche Software installiert ist. Datensparsamer ist die Synchronisierung des Gesamtbestands über Änderungszeiträume mit lokalem Abgleich (Empfehlung für die Umsetzung in Etappe 2).

### CISA KEV und EPSS

- **Was:** Liste aktiv ausgenutzter Lücken (KEV) und Ausnutzungswahrscheinlichkeit (EPSS).
- **Datenschutz:** Beide werden als Gesamtliste geladen; es fließen keine Inventardaten ab.
- **Bedingungen:** KEV ist gemeinfrei (CC0). EPSS ist frei nutzbar; Quellenangabe in der App.

### OSV.dev und GitHub Advisory Database

- **Was:** Schwachstellen in Open-Source-Paketen.
- **Datenschutz:** Abfragen enthalten Paketname und Version.
- **Bedingungen:** Daten stehen unter der Lizenz ihrer Ursprungsdatenbank (GitHub Advisory Database: CC BY 4.0, Namensnennung).

### Claude API (Anthropic)

- **Was:** Der KI-Berater schickt die Unterhaltung und die Ergebnisse der Werkzeugaufrufe (z. B. Programmliste mit Versionen, gefundene CVEs) an das Modell.
- **Bereinigung vor dem Senden:** Benutzername, Rechnername und Benutzerpfade (`C:\Users\<Name>\…`) werden durch Platzhalter ersetzt. Das ist eine **Pseudonymisierung, keine Anonymisierung**: Eine Liste installierter Software kann einen Rechner trotzdem kennzeichnen. Im Firmeneinsatz gilt die DSGVO daher weiter.
- **Bedingungen (Stand Oktober 2026, vor Nutzung prüfen):** Die API fällt unter die Commercial Terms von Anthropic, auch bei privater Nutzung. Laut Anthropic werden API-Eingaben nicht zum Training verwendet und standardmäßig nach 30 Tagen gelöscht; längere Speicherung ist bei Verstößen gegen die Nutzungsrichtlinie möglich. „Zero Data Retention“ gibt es nur nach Vereinbarung. Die Verarbeitung erfolgt in den USA.
- **Kosten:** Abrechnung nach Tokens über das Konto des Nutzers. Die App zeigt den Verbrauch an (geplant).
- **Firmen:** Auftragsverarbeitung, Drittlandübermittlung und Alternativen siehe [FIRMENEINSATZ.md](FIRMENEINSATZ.md).
- **Umfang:** begrenzt durch die Freigabestufe (Voreinstellung extern: Stufe 1, nur Programmliste).
- **Was nie gesendet wird:** API-Schlüssel, Inhalte von Dateien, Protokolle mit Benutzernamen, Hashes von Dateien aus privaten Ordnern.

### Lokale KI (Ollama, LM Studio)

- **Was:** Das Modell läuft auf dem eigenen Rechner; nichts verlässt ihn. Datenschutzrechtlich die einfachste Wahl.
- **Beachten:** Ollama lauscht standardmäßig nur auf `localhost`. Wer es im Netzwerk freigibt (`OLLAMA_HOST=0.0.0.0`), sollte den Zugriff per Firewall beschränken, da Ollama keine Anmeldung kennt. Läuft Ollama auf einem Server im Firmennetz, gehen die Daten dorthin; dann gilt dasselbe wie für jeden internen Dienst.
- **Lizenzen:** Jedes Modell hat eine eigene Lizenz. Für Firmen eignen sich Modelle unter Apache-2.0 oder MIT am einfachsten; bei Llama und Gemma die jeweiligen Bedingungen lesen.
- **Qualität:** Kleine lokale Modelle beherrschen Tool-Aufrufe unterschiedlich gut. Das Standardmodell ist noch offen.

### Web-Recherche des Beraters

- **Was:** Für unbekannte Programme kann der Berater im Web suchen. Ergebnisse gelten als „unbestätigt“.
- **Datenschutz:** Suchbegriffe enthalten meist Programmnamen, ggf. Hersteller. Benutzerdaten werden nicht in Suchanfragen übernommen. Welcher Suchanbieter die Anfragen erhält, hängt von der Umsetzung ab und wird in den Einstellungen genannt.

### Installierter Virenschutz (z. B. Bitdefender, Microsoft Defender)

Idee für einen späteren Ausbau, noch nicht umgesetzt und nicht getestet.

- **Bitdefender für Privatkunden** (Total Security, Premium Security) hat nach unserer Recherche **keine öffentliche Schnittstelle** und keinen offiziellen Befehlszeilen-Scanner. Eine direkte Anbindung „Bitdefender, prüfe diese Datei und sag mir das Ergebnis“ gibt es daher nicht.
- **Herstellerunabhängig über Windows** geht trotzdem einiges, und zwar mit jedem Virenschutz, der sich bei Windows anmeldet:
  - **Status:** Welcher Virenschutz installiert ist, ob er aktiv ist und ob die Signaturen aktuell sind, liefert das Windows-Sicherheitscenter (WMI `root\SecurityCenter2`, Klasse `AntiVirusProduct`). Nur lesen, Benutzerrechte genügen. Das ist ein sinnvoller Punkt für die Sicherheitsampel („Virenschutz aktiv und aktuell“).
  - **Datei prüfen lassen:** Über die Windows-Schnittstellen AMSI (Antimalware Scan Interface) oder den Anlagen-Dienst (`IAttachmentExecute`, wie ihn Browser für Downloads nutzen) kann die App eine Datei dem installierten Virenschutz zur Prüfung übergeben. Ob Bitdefender dabei ein verwertbares Ergebnis zurückgibt, muss getestet werden.
  - **Microsoft Defender** bietet zusätzlich PowerShell-Befehle (`Get-MpComputerStatus`, `Get-MpThreat`, `Start-MpScan`), aber nur, wenn Defender der aktive Virenschutz ist.
- **Firmen:** Business-Produkte haben echte Schnittstellen, z. B. die Public API von Bitdefender GravityZone oder die API von Microsoft Defender for Endpoint. Sie lassen sich als eigener Dienst (Klasse C) anbinden, um Funde und Schutzstatus pro Rechner einzublenden.
- **Datenschutz:** Die lokale Prüfung verlässt den Rechner nicht über unsere App. Viele Virenscanner melden Funde oder Dateimerkmale aber an die Cloud des Herstellers; das richtet sich nach den Einstellungen des Virenschutzes selbst.

### VirusTotal (optional)

- **Was:** Abgleich des SHA256-Hashs einer unbekannten Datei mit der VirusTotal-Datenbank.
- **Nur Hashes:** Die App lädt niemals Dateien hoch. Hochgeladene Dateien werden bei VirusTotal mit Sicherheitsfirmen geteilt und sind für zahlende Kunden abrufbar; bei internen oder vertraulichen Programmen wäre das ein Datenabfluss.
- **Bedingungen:** Die öffentliche (kostenlose) API **darf nicht in kommerziellen Produkten oder geschäftlichen Abläufen** verwendet werden und ist auf 4 Anfragen pro Minute und 500 pro Tag begrenzt. Deshalb Klasse B: Die App zeigt diesen Hinweis beim Einschalten; geschäftlich ist ein Premium-Schlüssel nötig.
- **Zustimmung:** Abfrage nur nach ausdrücklicher Einwilligung, einzeln oder pro Scan.

## Empfehlungen für Nutzer

| Situation | Empfehlung |
| --- | --- |
| Privat, maximaler Datenschutz | Lokale KI (Ollama), Online-Quellen KEV und EPSS an, NVD mit Gesamtabgleich, VirusTotal aus |
| Privat, beste Beratung | Claude API mit Vorschau der gesendeten Daten; Bereinigung eingeschaltet lassen |
| Firma | Vorher [FIRMENEINSATZ.md](FIRMENEINSATZ.md) durcharbeiten; Cloud-KI erst nach Datenschutzprüfung, VirusTotal nur mit Premium |
| Ohne Internet | Nur Inventar; Abgleich später nachholen |
