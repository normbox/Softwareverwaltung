# Einsatz in Unternehmen

Stand: 24.10.2026

Das Programm ist zunächst für den privaten Einsatz gedacht. Wer es in einem Unternehmen, einer Behörde oder einem Verein nutzen will, findet hier die Punkte, die vorher zu klären sind. Die Liste richtet sich an IT-Verantwortliche, Datenschutzbeauftragte und Betriebsräte.

> **Keine Rechtsberatung.** Diese Checkliste nennt typische Themen nach deutschem und europäischem Recht. Ob und wie sie im Einzelfall greifen, entscheidet die einsetzende Organisation mit ihrem Datenschutzbeauftragten und ggf. einer Rechtsberatung.

## Kurzfassung

| Ausbaustufe | Aufwand Datenschutz | Wichtigster Punkt |
| --- | --- | --- |
| Nur Inventar, lokal, ohne Tiefenscan | gering | Information der Beschäftigten, Eintrag im Verarbeitungsverzeichnis |
| + Online-Abgleich (NVD, KEV, EPSS, GitHub, winget) | gering | Firewall-Freigaben; keine Personendaten in den Abfragen |
| + Tiefenscan (Nutzungsspuren) | **hoch** | Verhaltensdaten der Beschäftigten → Betriebsrat, Zweckbindung |
| + KI-Berater lokal (Ollama im Haus) | mittel | Betrieb und Absicherung des KI-Servers |
| + KI-Berater Cloud (Claude API) | **hoch** | Auftragsverarbeitung, Drittland USA, ggf. DSFA |
| + zentrale Sammlung mehrerer PCs (Etappe 6) | **hoch** | Zugriffskonzept, Löschfristen, Mitbestimmung |

## 1. DSGVO-Grundlagen

- **Verantwortlicher** ist die einsetzende Organisation, nicht das Open-Source-Projekt.
- **Rechtsgrundlage:** Für ein Software- und Schwachstelleninventar kommt typischerweise das berechtigte Interesse an der IT-Sicherheit in Betracht (Art. 6 Abs. 1 lit. f DSGVO, Erwägungsgrund 49) sowie rechtliche Pflichten zur Sicherheit der Verarbeitung (Art. 32 DSGVO) und je nach Branche NIS2-Umsetzung. Hinweis: § 26 BDSG ist nach dem EuGH-Urteil C-34/21 (2023) als eigenständige Grundlage für Beschäftigtendaten nur eingeschränkt tragfähig; die Begründung sollte auf die DSGVO selbst gestützt werden.
- **Zweckbindung:** Zweck ist IT-Sicherheit und Softwarepflege, **nicht** Leistungs- oder Verhaltenskontrolle. Das sollte schriftlich festgehalten und technisch unterstützt werden (Nutzungsspuren aus, Startzähler nicht auswerten).
- **Informationspflicht** (Art. 13 DSGVO): Beschäftigte darüber informieren, welche Daten erhoben werden und wozu.
- **Verzeichnis der Verarbeitungstätigkeiten** (Art. 30 DSGVO): Eintrag anlegen; die Tabellen in [PRIVACY.md](../PRIVACY.md) und [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md) helfen dabei.
- **Löschkonzept:** Aufbewahrungsdauer für Scans, Protokolle und Chatverläufe festlegen (z. B. Scans 90 Tage, Aktionsprotokoll 1 Jahr).
- **Technische und organisatorische Maßnahmen** (Art. 32 DSGVO): Wer darf Scans anderer Rechner sehen? Wo liegen sie? Sind sie verschlüsselt (z. B. BitLocker)?

## 2. Nutzungsspuren und Mitbestimmung

Der Tiefenscan (Etappe 1b) liest Amcache, BAM, UserAssist und Prefetch. Daraus lässt sich ablesen, **wer wann welches Programm wie oft gestartet hat**.

- In Deutschland ist eine technische Einrichtung, die objektiv geeignet ist, Verhalten oder Leistung von Beschäftigten zu überwachen, nach **§ 87 Abs. 1 Nr. 6 BetrVG** mitbestimmungspflichtig. Auf die Absicht kommt es nicht an. Ein Inventar mit Nutzungsspuren fällt sehr wahrscheinlich darunter, ein reines Installationsinventar möglicherweise auch.
- Empfehlung: Vor dem Einsatz mit dem Betriebsrat (bzw. Personalrat) eine Vereinbarung treffen, die Zweck, Datenumfang, Zugriffsrechte, Löschfristen und ein Auswertungsverbot für Verhaltensdaten regelt.
- Technisch: Den Tiefenscan nicht einschalten (er ist standardmäßig aus) bzw. per Richtlinie sperren oder auf „Programme finden, Zeitstempel verwerfen“ beschränken (Umsetzung vorgesehen).

## 3. KI-Berater in der Cloud (Claude API)

| Thema | Was zu tun ist |
| --- | --- |
| Auftragsverarbeitung (Art. 28 DSGVO) | Anthropic stellt für kommerzielle Kunden ein Data Processing Addendum bereit, das Bestandteil der Commercial Terms ist. Prüfen, ob es für den eigenen Fall genügt, und dokumentieren. |
| Drittlandübermittlung (Art. 44 ff. DSGVO) | Verarbeitung in den USA. Prüfen, ob der Anbieter unter dem EU-US Data Privacy Framework zertifiziert ist bzw. welche Standardvertragsklauseln gelten. |
| Freigabestufe | Per Richtlinie die höchste Stufe für externe KI festlegen, empfohlen Stufe 1 (Programmliste); Nutzungsspuren nie extern. Siehe [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md#was-die-ki-sehen-darf-freigabestufen). |
| Datenminimierung | Bereinigung (Benutzer, Rechner, Pfade) eingeschaltet lassen; zusätzlich Domänennamen und interne Programmnamen ersetzen (Liste konfigurierbar, geplant). |
| Speicherdauer beim Anbieter | Standard laut Anthropic 30 Tage, kein Training mit API-Daten; Zero Data Retention nur nach Vereinbarung. Aktuellen Stand prüfen. |
| Alternativen | Lokales Modell (Ollama im eigenen Netz) oder Claude über einen Cloud-Anbieter mit EU-Region (z. B. AWS Bedrock, Google Cloud Vertex AI), sofern die App diesen Provider unterstützt (derzeit nicht geplant, bei Bedarf als weiterer Provider). |
| Datenschutz-Folgenabschätzung (Art. 35 DSGVO) | Bei Kombination aus Beschäftigtendaten, Verhaltensdaten und KI in der Cloud wahrscheinlich nötig; mit dem Datenschutzbeauftragten klären. |
| Geschäftsgeheimnisse | Interne Programme und Versionsstände können vertraulich sein. Entscheiden, ob sie die Organisation verlassen dürfen. |
| API-Schlüssel | Firmenkonto bei Anthropic statt privater Schlüssel; Ausgabenlimit setzen; Schlüssel zentral verteilen und regelmäßig erneuern. |

## 4. EU-KI-Verordnung (AI Act)

- Der Berater ist ein KI-System mit begrenztem Risiko; er trifft keine Entscheidungen über Menschen.
- **Transparenz** (Art. 50, anwendbar seit 2. August 2026): Nutzer müssen erkennen, dass sie mit einer KI sprechen. Die App kennzeichnet den Berater deutlich als KI und seine Vorschläge als maschinell erzeugt.
- **KI-Kompetenz** (Art. 4, seit 2. Februar 2025): Organisationen, die KI-Systeme einsetzen, sollen für ausreichende Kenntnisse der Nutzer sorgen. Eine kurze Einweisung („Die KI schlägt nur vor; Ergebnisse aus Web-Recherche sind unbestätigt“) genügt hier in der Regel.

## 5. Lizenzen und Nutzungsbedingungen im Firmeneinsatz

| Punkt | Hinweis |
| --- | --- |
| Softwareverwaltung selbst | GPLv3: Nutzung in der Firma ohne Einschränkung. Pflichten (Quellcode, Lizenztext) entstehen erst bei **Weitergabe** an Dritte, nicht bei interner Nutzung. Interne Anpassungen müssen nicht veröffentlicht werden. |
| Einrichtung | Alle Dienste sind anfangs aus und werden einzeln eingerichtet. Die Hinweise zu den Nutzungsbedingungen beim Einschalten beachten. Einstellungen lassen sich optional per Richtlinie festlegen und sperren, siehe [EXTERNE-DIENSTE.md](EXTERNE-DIENSTE.md#dienste-einrichten-alles-manuell-für-alle-gleich). |
| VirusTotal | Die kostenlose öffentliche API ist für geschäftliche Abläufe **nicht erlaubt**. Nur mit Premium-Schlüssel einschalten. |
| GitHub, NVD | Je Organisation eigene Schlüssel bzw. Tokens; Abfragegrenzen hinter gemeinsamem Proxy beachten. NVD-Schlüssel nicht über viele Installationen teilen, sondern zentral abrufen und Ergebnisse cachen (Etappe 6). |
| Microsoft Store (`msstore`) | Zustimmung zur Quellvereinbarung durch die Organisation; ggf. Quelle per Richtlinie sperren. |
| Lokale Sprachmodelle | Lizenz des gewählten Modells für kommerzielle Nutzung prüfen; Modelle unter Apache-2.0 oder MIT sind am einfachsten. |
| Claude API | Commercial Terms und Usage Policy von Anthropic gelten für die Organisation. |

## 6. IT-Betrieb

- **Firewall/Proxy:** Hostliste in [TECHNIK.md](TECHNIK.md#netzwerkverbindungen).
- **Rechte:** Die App läuft ohne Administratorrechte; Tiefenscan und Aktionen fordern UAC an. In verwalteten Umgebungen Aktionen besser über die vorhandene Softwareverteilung (Intune, SCCM, winget-Richtlinien) auslösen und die App nur zur Analyse nutzen.
- **Ausführungsrichtlinien:** Für AppLocker/WDAC sind signierte Releases und signierte Skripte vorgesehen (Etappe 6). Bis dahin: Hash-Regel oder Ausnahme für das Installationsverzeichnis.
- **Telemetrie Dritter:** winget-Telemetrie und PowerShell-Telemetrie per Richtlinie bzw. Umgebungsvariable abschalten (siehe [TECHNIK.md](TECHNIK.md#telemetrie)).
- **Updates der App:** keine Selbstaktualisierung im Hintergrund; neue Versionen über die eigene Softwareverteilung.

## 7. Checkliste vor dem Start

- [ ] Einstellungen festgelegt, ggf. per Richtlinie gesperrt
- [ ] Zweck und Umfang festgelegt (mit oder ohne Tiefenscan, mit oder ohne Cloud-KI)
- [ ] Datenschutzbeauftragten beteiligt; Eintrag im Verarbeitungsverzeichnis
- [ ] Betriebs-/Personalrat beteiligt, Vereinbarung geschlossen
- [ ] Beschäftigte informiert
- [ ] Bei Cloud-KI: Auftragsverarbeitung und Drittlandübermittlung geprüft, ggf. DSFA durchgeführt
- [ ] Höchste KI-Freigabestufe je Anbieter per Richtlinie gesetzt, interne Programme auf die Ausschlussliste
- [ ] Löschfristen eingestellt
- [ ] Externe Dienste einzeln bewertet und nur benötigte aktiviert; VirusTotal nur mit Premium
- [ ] Firewall-Freigaben und Telemetrie-Einstellungen gesetzt
- [ ] Schlüssel (Anthropic, NVD, GitHub) im Organisationskonto, nicht privat
- [ ] Einweisung der Nutzer in den KI-Berater
