# Rechtliche Hinweise

Stand: 28.10.2026

> **Keine Rechtsberatung.** Diese Seite fasst zusammen, was beim Entwickeln, Veröffentlichen und Nutzen dieses Open-Source-Projekts rechtlich zu beachten ist. Sie ist nach bestem Wissen recherchiert, ersetzt aber keine anwaltliche Beratung. Bei Zweifeln, besonders vor einem kommerziellen Angebot, bitte fachkundig beraten lassen.

## 1. Lizenz des Projekts

- Softwareverwaltung steht unter der **GNU General Public License v3.0** ([LICENSE](../LICENSE)).
- Jeder darf das Programm nutzen, untersuchen, ändern und weitergeben, auch kommerziell.
- Wer es **weitergibt** (auch verändert), muss es wieder unter GPLv3 stellen, den Lizenztext beilegen und den Quellcode zugänglich machen. Interne Nutzung in einer Firma löst diese Pflichten nicht aus.
- Beiträge (Pull Requests) werden unter derselben Lizenz eingebracht („inbound = outbound“). Ein eigener Contributor License Agreement ist nicht vorgesehen. Empfehlung: In `CONTRIBUTING.md` festhalten, dass Beitragende mit dem Einreichen bestätigen, die Rechte am Beitrag zu haben (z. B. per Developer Certificate of Origin, `git commit -s`).
- Kopfzeile für Quelldateien (optional, empfohlen): `SPDX-License-Identifier: GPL-3.0-or-later` bzw. `GPL-3.0-only`. **Offen:** Entscheidung „only“ oder „or-later“. „or-later“ erlaubt künftige GPL-Versionen und ist bei GNU üblich; „only“ legt sich fest. Das Modulmanifest verweist derzeit auf GPLv3 ohne Zusatz.

Drittkomponenten und ihre Lizenzen: [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## 2. Gewährleistung und Haftung

- Die GPLv3 schließt Gewährleistung und Haftung weitgehend aus (Abschnitte 15 und 16), soweit das Recht es zulässt.
- In Deutschland ist ein vollständiger Ausschluss nicht wirksam. Bei unentgeltlicher Überlassung wird überwiegend eine Haftung nur für **Vorsatz und grobe Fahrlässigkeit** angenommen (Rechtsgedanke der Schenkung, §§ 521, 524 BGB). Arglistig verschwiegene Mängel und Produkthaftung bleiben unberührt.
- Praktisch heißt das: sorgfältig entwickeln, bekannte Risiken dokumentieren, Aktionen nur nach Bestätigung ausführen. Genau dafür gibt es Bestätigungsdialoge mit dem genauen Befehl (Standard-Button „Abbrechen“), optionale Wiederherstellungspunkte und das Aktionsprotokoll.
- Hinweis in der App (Vorschlag, noch nicht umgesetzt): „Updates und Deinstallationen verändern Ihr System. Erstellen Sie vorher eine Sicherung. Die Ausführung erfolgt auf eigene Verantwortung.“ Das README enthält einen entsprechenden Haftungshinweis.

## 3. Sicherheitsbewertungen und KI-Aussagen

- Ampel, CVE-Zuordnung und Versionsvergleich beruhen auf öffentlichen Datenquellen und auf Zuordnungen aus dem Katalog bzw. vom Nutzer. Sie können **falsch oder unvollständig** sein (falsche CPE-Zuordnung, verspätete Einträge, fehlende Herstellerdaten).
- Antworten des KI-Beraters sind maschinell erzeugt und können falsch sein. Ergebnisse aus Web-Recherche sind als „unbestätigt“ gekennzeichnet.
- Das Programm ersetzt keine professionelle Schwachstellenanalyse und keinen Virenschutz. Ein grünes Ampelsignal bedeutet nur, dass in den abgefragten Quellen nichts gefunden wurde. Grau heißt „nicht geprüft“, immer mit Grund.
- Diese Hinweise gehören in die App („Über“ und Erstbenutzung) und ins README.

## 4. Nutzungsbedingungen der Datenquellen

Die App verwendet Daten und Schnittstellen Dritter. Deren Bedingungen gelten für jeden Nutzer selbst. Die wichtigsten Punkte:

| Quelle | Wichtigste Bedingung |
| --- | --- |
| NVD | Pflichthinweis „This product uses the NVD API but is not endorsed or certified by the NVD.“; Abfragegrenzen; Schlüssel nicht weitergeben |
| CISA KEV | gemeinfrei (CC0) |
| EPSS | frei nutzbar, Quellenangabe erbeten |
| GitHub API | GitHub Terms of Service, Abfragegrenzen |
| winget / Microsoft Store | Quellvereinbarungen von Microsoft; Zustimmung durch den Nutzer (bei Store-Paketen offen, siehe Abschnitt 8) |
| Lokale Sprachmodelle | Lizenz des gewählten Modells |

Weitere Dienste (z. B. Cloud-KI, CIRCL) werden hier ergänzt, sobald sie umgesetzt sind.

Einzelheiten: [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md) und [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

**Produktkatalog:** Der Katalog im Repository enthält Erkennungsmuster, CPE-Namen und GitHub-Repositorys, keine Daten der Dienste. **Herstellerregeln (geplant):** Regeln, die Versionsnummern von Hersteller-Webseiten lesen, sollen offizielle Update-Feeds, APIs oder Download-Seiten nutzen, die `robots.txt` und die Nutzungsbedingungen der Seite beachten, selten abfragen (Cache) und keine Zugangsbeschränkungen umgehen. Regeln, die das nicht einhalten, werden nicht aufgenommen.

## 5. Marken und Namen

- „Windows“, „winget“, „Microsoft Store“, „PowerShell“, „Claude“, „Anthropic“, „GitHub“, „VirusTotal“, „Ollama“, „LM Studio“, „Unsloth“ und weitere sind Marken ihrer Inhaber. Das Projekt nennt sie nur, um die Zusammenarbeit zu beschreiben, und verwendet keine fremden Logos.
- Formulierungen wie „für Windows“ oder „unterstützt Claude“ sind zulässig; nicht zulässig ist der Eindruck einer Partnerschaft oder Empfehlung („offizielles Microsoft-Tool“, „von Anthropic zertifiziert“).
- **Projektname:** Vor der endgültigen Festlegung im Register des DPMA und der EUIPO (TMview) sowie auf GitHub nach gleichnamigen Software-Produkten suchen. „Softwareverwaltung“ ist beschreibend und als Marke kaum schutzfähig, aber auch kaum angreifbar.

## 6. Analyse des eigenen Systems

- Das Auslesen von Registry, Nutzungsspuren und Programmdateien auf dem **eigenen** Rechner ist unproblematisch.
- Auf Rechnern anderer Personen (Familie, Kunden, Beschäftigte) nur mit deren Wissen bzw. auf geeigneter Rechtsgrundlage; siehe [PRIVACY.md](../PRIVACY.md) und [FIRMENEINSATZ.md](FIRMENEINSATZ.md).
- Programmdateien werden nicht verändert, nicht entschlüsselt und nicht ausgeführt; es werden keine Kopierschutzmaßnahmen umgangen.

## 7. Regulierung, die später wichtig werden kann

| Regelung | Bedeutung für das Projekt |
| --- | --- |
| **Cyber Resilience Act (EU 2024/2847)** | Gilt für Produkte, die im Rahmen einer **Geschäftstätigkeit** auf den Markt gebracht werden. Ein unentgeltliches, nicht kommerziell betriebenes Open-Source-Projekt fällt nicht darunter. Wird das Programm später verkauft, mit Support-Verträgen angeboten oder von einem Unternehmen vertrieben, gelten die Meldepflichten (seit 11.09.2026) und die übrigen Anforderungen (ab 11.12.2027). Ein Prozess für Sicherheitsmeldungen (`SECURITY.md`, private Meldung über GitHub) ist auch ohne Pflicht sinnvoll. |
| **EU-KI-Verordnung** | Transparenzpflicht: Der Berater wird als KI gekennzeichnet. Kein Hochrisiko-System. Details in [FIRMENEINSATZ.md](FIRMENEINSATZ.md#4-eu-ki-verordnung-ai-act). |
| **Produkthaftungsrichtlinie (EU 2024/2853)** | Erfasst künftig auch Software; freie Open-Source-Software außerhalb einer Geschäftstätigkeit ist ausgenommen. Bei kommerziellem Vertrieb neu bewerten. |
| **Impressumspflicht (§ 5 DDG)** | Für ein privates GitHub-Repository ohne geschäftlichen Charakter in der Regel nicht nötig. Eine eigene Projektwebseite mit geschäftsmäßigem Bezug (Spenden-Aufrufe, Werbung, Verkauf) kann eine Impressumspflicht auslösen. |

## 8. Offene Punkte für das Projekt

- [ ] `GPL-3.0-only` oder `GPL-3.0-or-later` festlegen und im Modulmanifest, README und ggf. Dateiköpfen eintragen
- [ ] `CONTRIBUTING.md` mit Hinweis auf DCO bzw. Rechte an Beiträgen
- [ ] `SECURITY.md` anlegen und „Private vulnerability reporting“ in den Repository-Einstellungen auf GitHub aktivieren
- [x] Lizenz von `Microsoft.WinGet.Client` geklärt: MIT, Mitliefern erlaubt (mit Lizenztext und NOTICE)
- [ ] Hinweistexte vollständig in die App übernehmen: Seite „Über“ mit NVD-, KEV- und EPSS-Hinweis (stehen bisher nur bei den Hinweisen zu den Nutzungsbedingungen), KI-Kennzeichnung (Etappe 4c), Haftungshinweis im Bestätigungsdialog
- [x] Updates von Store-Paketen (`msstore`): Zustimmung zur Quellvereinbarung sichtbar machen statt `--accept-source-agreements` im Befehl
- [ ] Projektnamen vor der Festlegung auf Marken prüfen
