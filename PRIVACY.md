# Datenschutz

Stand: 28.10.2026

Softwareverwaltung ist ein Programm, das man auf dem eigenen Rechner ausführt. Es gibt **keinen Server des Projekts**, kein Benutzerkonto und keine Telemetrie. Die Projektverantwortlichen erhalten keine Daten der Nutzer.

Wer das Programm einsetzt, ist für die damit verarbeiteten Daten selbst verantwortlich. Diese Seite erklärt, welche Daten anfallen, wo sie bleiben und wann sie den Rechner verlassen, damit Nutzer das beurteilen können.

> **Keine Rechtsberatung.** Diese Hinweise beschreiben die Technik und geben eine allgemeine Einordnung nach DSGVO. Für einen konkreten Einsatz, besonders in Unternehmen, Behörden oder Vereinen, ist der eigene Datenschutzbeauftragte bzw. eine Rechtsberatung zuständig.

## 1. Welche Daten das Programm verarbeitet

| Daten | Beispiel | Personenbezug |
| --- | --- | --- |
| Liste installierter Programme | Name, Version, Hersteller, Installationsart | indirekt: kennzeichnet einen Rechner und damit oft eine Person |
| Installationspfade, Deinstallationsbefehle | `C:\Users\anna\AppData\Local\Programs\…` | ja, wenn der Benutzername im Pfad steht |
| Benutzerbezogene Installationen (HKCU) | Programme nur des angemeldeten Benutzers | ja |
| Rechnername, Benutzername | aus der Umgebung | ja |
| **Nutzungsspuren** (nur wenn eingeschaltet): UserAssist, laufende Prozesse, Autostart, geplante Aufgaben | „Programm X zuletzt gestartet am …“ | **ja, beschreibt Verhalten** |
| Dateisuche in gewählten Laufwerken oder Ordnern (nur wenn eingeschaltet) | Dateiname, Pfad, Version, Signatur, optional Hash von `.exe`-Dateien | ja, Pfade und Dateinamen können persönlich sein |
| Aktionsprotokoll | „Update von 7-Zip am … durch Benutzer …“ | ja |
| Chatverlauf mit dem KI-Berater (geplant, Etappe 4c) | Fragen und Antworten | je nach Inhalt |

Nicht verarbeitet werden: Inhalte von Dokumenten, Browserverlauf, E-Mails, Passwörter. Programmdateien werden nur gelesen (Versionsinfo, Signatur, Hash), nie ausgeführt. Amcache, BAM und Prefetch liest das Programm nicht.

## 2. Wo die Daten bleiben

Ausschließlich auf dem eigenen Rechner im Benutzerprofil. Einzelheiten in [docs/TECHNIK.md](docs/TECHNIK.md#datenablage).

- `%LOCALAPPDATA%\SoftwareInventory`: Aktionsprotokoll, Installer-Logs nach Fehlern, Zwischenspeicher der Online-Abfragen, Fehlerprotokoll der App, gespeicherte Scans.
- `%APPDATA%\SoftwareInventory`: Einstellungen und eigene CPE-Zuordnungen.
- **Automatische Bereinigung:** Protokolle und Zwischenspeicher werden beim Start aufgeräumt, höchstens 30 Tage alt und höchstens 100 MB insgesamt (beides einstellbar, Ältestes zuerst). Installer-Logs werden nach erfolgreicher Aktion sofort gelöscht.
- **Scans:** Die App speichert keine Scans. Gespeichert wird nur, wer im Modul ausdrücklich `Save-InventorySnapshot` aufruft. Diese Dateien bleiben, bis man sie löscht.
- API-Schlüssel liegen in der Windows-Anmeldeinformationsverwaltung, nicht in Dateien.

## 3. Wann Daten den Rechner verlassen

Nur wenn Online-Funktionen eingeschaltet sind. Alle sind nach der Installation aus und werden einzeln eingeschaltet. Die vollständige Liste mit übertragenen Inhalten, Empfängern und Bedingungen steht in **[docs/EXTERNE-DIENSTE.md](docs/EXTERNE-DIENSTE.md)**.

Kurz:

- **winget-Daten und Updates** (Microsoft): winget liest seine Paketkataloge. Bei einem Update lädt winget das Installationsprogramm. Die winget-Suche nach neuen Versionen sendet Paket-IDs oder Programmnamen an die winget-Quellen.
- **Versions- und Sicherheitsabgleich** (GitHub, NVD, CISA KEV, FIRST EPSS): Je nach Dienst werden Repository-Namen, Produktkennungen (CPE) mit Version oder CVE-Nummern abgefragt, bei KEV nur die Gesamtliste. Keine Benutzer- oder Rechnernamen, keine Pfade.
- **KI-Berater** (geplant, Etappe 4b/4c): vorerst nur mit lokalen Modellservern (Ollama, LM Studio, Unsloth Studio oder eine eigene Adresse). Auf dem eigenen Rechner verlässt nichts den Rechner. Bei einer eigenen Adresse im Netz gehen die Daten an diesen Server. Benutzername, Rechnername und Benutzerpfade werden immer vorher ersetzt, auch für lokale Modelle. Cloud-Anbieter (z. B. die Claude API) kommen erst später als Erweiterung dazu und werden dann hier ergänzt.
- **„Vorschlag melden“** (geplant): Wer eine bestätigte CPE-Zuordnung als Verbesserung für den Katalog melden möchte, bekommt ein vorbereitetes GitHub-Issue im Browser. Es enthält Programmname, Hersteller, winget-ID und CPE, keine Pfade und keine Benutzer- oder Rechnernamen. Abgeschickt wird es nur vom Nutzer selbst, und das Issue ist öffentlich.

**Microsoft Store (`msstore`):** Bei Paketen aus der Quelle `msstore` zeigt die App vor dem ersten Update oder der ersten Deinstallation einmal die Vereinbarung der Store-Quelle (Standard-Button „Abbrechen“). Erst nach Zustimmung, die in den Einstellungen gespeichert wird, enthält der Befehl `--accept-source-agreements`; ohne Zustimmung ist die Aktion nicht ausführbar (Grund `StoreAgreementRequired`). Die Store-Quelle übermittelt dabei unter anderem den Ländercode des Rechners (z. B. „DE“) an Microsoft.

**Telemetrie von PowerShell:** Die App setzt `POWERSHELL_TELEMETRY_OPTOUT=1` für die eingebettete PowerShell und für den erhöhten Helfer. Der Helfer läuft unter Windows PowerShell 5.1; dieses kennt die Variable nicht, seine Diagnosedaten folgen den Windows-Diagnoseeinstellungen. Die Telemetrie von winget folgt ebenfalls den Windows-Diagnoseeinstellungen und lässt sich in `winget settings` abschalten.

Alle derzeit angebundenen Empfänger sitzen in den USA (Microsoft, GitHub, NIST, CISA, FIRST). Bei jeder Verbindung erhält der Anbieter die IP-Adresse.

## 4. Einordnung nach DSGVO

### Private Nutzung

Wer das Programm ausschließlich für persönliche oder familiäre Zwecke auf dem eigenen Rechner nutzt, fällt nach Art. 2 Abs. 2 lit. c DSGVO („Haushaltsausnahme“) in der Regel nicht unter die DSGVO. Trotzdem empfehlenswert:

- Teilen sich mehrere Personen den Rechner, die anderen informieren, bevor die Nutzungsspuren ausgewertet werden, und sie nur bei Bedarf einschalten.
- Für den KI-Berater ein Modell auf dem eigenen Rechner bevorzugen.

### Einsatz in Unternehmen, Behörden, Vereinen

Dann ist die einsetzende Organisation Verantwortliche im Sinne der DSGVO, und es gelten unter anderem Rechtsgrundlage, Informationspflichten, Verzeichnis der Verarbeitungstätigkeiten, ggf. Auftragsverarbeitung und Datenschutz-Folgenabschätzung sowie in Deutschland die Mitbestimmung des Betriebsrats. Eine Checkliste steht in **[docs/FIRMENEINSATZ.md](docs/FIRMENEINSATZ.md)**.

## 5. Datenschutz durch Technik (Grundsätze für die Entwicklung)

Diese Regeln gelten für jeden Beitrag zum Projekt:

1. **Lokal zuerst.** Neue Funktionen müssen ohne Cloud nutzbar sein. Online-Dienste sind Ergänzungen und standardmäßig aus.
2. **Datensparsam abfragen.** Gesamtlisten laden und lokal vergleichen, wo der Dienst das erlaubt.
3. **Bereinigen vor dem Senden.** Benutzername, Rechnername, Benutzerpfade, Domänennamen und E-Mail-Adressen werden vor jeder Übertragung an eine KI ersetzt (`Protect-PrivateText`), auch an lokale Modelle. Neue Felder im Datensatz sind daraufhin zu prüfen.
4. **Nutzungsspuren getrennt halten.** Nutzungsspuren werden nur gelesen, wenn sie in den Einstellungen eingeschaltet sind. Genaue Zeitstempel, Startzähler und Benutzerzuordnung gehen an keine KI. Was die KI sieht, begrenzen Freigabestufen, die das Modul durchsetzt (geplant in Etappe 4b, siehe [docs/EXTERNE-DIENSTE.md](docs/EXTERNE-DIENSTE.md#was-die-ki-sehen-darf-freigabestufen)). Bis dahin geben die Werkzeuge des Beraters gar keine Nutzungsspuren weiter.
5. **Keine Telemetrie** des Projekts, auch keine „anonyme“.
6. **Sichtbar machen.** Die Einstellungen zeigen, welche Dienste aktiv sind und was sie erhalten.
7. **Löschbar und selbst aufräumend.** Protokolle und Zwischenspeicher bereinigen sich selbst. Alles, was gespeichert wird, lässt sich löschen.

## 6. Kontakt

Fragen und Hinweise zum Datenschutz des Programms bitte als Issue im Repository [normbox/Softwareverwaltung](https://github.com/normbox/Softwareverwaltung/issues). Sicherheitslücken bitte nicht öffentlich melden, sondern über die private Meldefunktion von GitHub („Report a vulnerability“).
