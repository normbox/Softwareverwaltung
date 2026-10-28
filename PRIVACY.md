# Datenschutz

Stand: 24.10.2026

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
| **Nutzungsspuren** (ab Etappe 1b): Amcache, BAM, UserAssist, Prefetch | „Programm X zuletzt gestartet am …, 37 Starts“ | **ja, beschreibt Verhalten**; bei mehreren Benutzern auch das anderer Personen |
| Dateiscan gewählter Ordner (ab 1b) | Dateiname, Pfad, Version, Signatur, Hash von `.exe`-Dateien | ja, Pfade und Dateinamen können persönlich sein |
| Chatverlauf mit dem KI-Berater | Fragen und Antworten | je nach Inhalt |
| Aktionsprotokoll | „Update von 7-Zip am … durch Benutzer …“ | ja |

Nicht verarbeitet werden: Inhalte von Dokumenten, Browserverlauf, E-Mails, Passwörter. Programmdateien werden nur gelesen (Versionsinfo, Signatur, Hash), nie ausgeführt.

## 2. Wo die Daten bleiben

Standardmäßig ausschließlich auf dem eigenen Rechner im Benutzerprofil (`%LOCALAPPDATA%\SoftwareInventory`, `%APPDATA%\SoftwareInventory`). Einzelheiten in [docs/TECHNIK.md](docs/TECHNIK.md#datenablage).

- Gespeicherte Scans lassen sich in der App oder durch Löschen des Ordners entfernen. Eine einstellbare automatische Löschung ist vorgesehen.
- API-Schlüssel liegen in der Windows-Anmeldeinformationsverwaltung, nicht in Dateien.

## 3. Wann Daten den Rechner verlassen

Nur wenn Online-Funktionen eingeschaltet sind. Jeder Dienst ist einzeln abschaltbar. Die vollständige Liste mit übertragenen Inhalten, Empfängern und Bedingungen steht in **[docs/EXTERNE-DIENSTE.md](docs/EXTERNE-DIENSTE.md)**.

Kurz:

- **Sicherheits- und Versionsabgleich** (NVD, CISA KEV, EPSS, OSV, GitHub, winget): Je nach Dienst werden Programmnamen, Produktkennungen oder Versionen abgefragt, sonst nur Gesamtlisten geladen. Keine Benutzer- oder Rechnernamen.
- **KI-Berater mit Cloud-Modell** (Claude API, standardmäßig aus): Unterhaltung und Werkzeugergebnisse gehen an Anthropic in den USA, im Umfang der gewählten Freigabestufe (Voreinstellung: nur Programmliste). Benutzername, Rechnername und Benutzerpfade werden vorher ersetzt. Eine Vorschau zeigt, was gesendet wird.
- **KI-Berater mit lokalem Modell** (Ollama): Es verlässt nichts den Rechner.
- **VirusTotal** (standardmäßig aus): nur Hashwerte, nur nach Zustimmung, nie Dateien.

Alle Empfänger sitzen in den USA. Bei jeder Verbindung erhält der Anbieter die IP-Adresse.

## 4. Einordnung nach DSGVO

### Private Nutzung

Wer das Programm ausschließlich für persönliche oder familiäre Zwecke auf dem eigenen Rechner nutzt, fällt nach Art. 2 Abs. 2 lit. c DSGVO („Haushaltsausnahme“) in der Regel nicht unter die DSGVO. Trotzdem empfehlenswert:

- Teilen sich mehrere Personen den Rechner, die anderen informieren, bevor der Tiefenscan (Nutzungsspuren) läuft, und ihn nur bei Bedarf einschalten.
- Für den KI-Berater das lokale Modell bevorzugen oder die Vorschau der gesendeten Daten ansehen.
- Für die Claude API gelten die Bedingungen von Anthropic auch für Privatpersonen; der Anbieter ist selbst für seine Verarbeitung verantwortlich.

### Einsatz in Unternehmen, Behörden, Vereinen

Dann ist die einsetzende Organisation Verantwortliche im Sinne der DSGVO, und es gelten unter anderem Rechtsgrundlage, Informationspflichten, Verzeichnis der Verarbeitungstätigkeiten, ggf. Auftragsverarbeitung und Datenschutz-Folgenabschätzung sowie in Deutschland die Mitbestimmung des Betriebsrats. Eine Checkliste steht in **[docs/FIRMENEINSATZ.md](docs/FIRMENEINSATZ.md)**.

## 5. Datenschutz durch Technik (Grundsätze für die Entwicklung)

Diese Regeln gelten für jeden Beitrag zum Projekt:

1. **Lokal zuerst.** Neue Funktionen müssen ohne Cloud nutzbar sein; Cloud-Dienste sind Ergänzungen und standardmäßig aus, wenn sie Inventardaten übertragen.
2. **Datensparsam abfragen.** Gesamtlisten laden und lokal vergleichen, wo der Dienst das erlaubt.
3. **Bereinigen vor dem Senden.** Benutzername, Rechnername, Benutzerpfade, Domänennamen und E-Mail-Adressen werden vor jeder Übertragung an eine KI ersetzt. Neue Felder im Datensatz sind daraufhin zu prüfen.
4. **Nutzungsspuren getrennt halten.** Amcache, BAM, UserAssist und Prefetch nur im ausdrücklich gestarteten Tiefenscan lesen. Genaue Zeitstempel, Startzähler und Benutzerzuordnung gehen an keine KI; was die KI sieht, begrenzen Freigabestufen, die das Modul durchsetzt (siehe [docs/EXTERNE-DIENSTE.md](docs/EXTERNE-DIENSTE.md#was-die-ki-sehen-darf-freigabestufen)).
5. **Keine Telemetrie** des Projekts, auch keine „anonyme“.
6. **Sichtbar machen.** Die Einstellungen zeigen, welche Dienste aktiv sind und was sie erhalten.
7. **Löschbar.** Alles, was gespeichert wird, lässt sich in der App löschen.

## 6. Kontakt

Fragen und Hinweise zum Datenschutz des Programms bitte als Issue im Repository [normbox/Softwareverwaltung](https://github.com/normbox/Softwareverwaltung/issues). Sicherheitslücken bitte nicht öffentlich melden, sondern über die private Meldefunktion von GitHub („Report a vulnerability“).
