# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Das Projekt ist noch nicht veröffentlicht; die Einträge sind nach Etappen gegliedert.

## Unveröffentlicht

### Sicherheitsprüfung: alle Dienste sichtbar, „lokal blockiert“ als eigener Grund

- **Nicht nur die NVD:** Liefern NVD, CIRCL, KEV oder EPSS in einem Lauf nichts, nennt die App das je Dienst, oben in der Liste (eine Zeile je Dienst mit Zahl der Programme und Grund) und in den Details. Ersetzt den NVD-Hinweis von unten.
- **Kein stiller Rückfall mehr:** Nimmt die App ältere gespeicherte Daten, weil ein Dienst nicht antwortet, steht das mit Datum (Ortszeit) und Grund dort ebenso („CIRCL: ältere gespeicherte Daten vom … verwendet“). Vorher war das nur am Vermerk „veraltet“ in der Spalte „Geprüft“ zu ahnen (Fall 08.11.: Bitdefender verwarf auch Verbindungen zu CIRCL, EPSS und KEV).
- **Windows-Fehler 10013 heißt jetzt „Verbindung auf diesem Rechner blockiert (Firewall oder Virenscanner)“** (Code `LocalBlocked`) statt der Windows-Meldung zu Socket-Zugriffsrechten. Andere Netzwerkfehler bleiben „nicht erreichbar“.
- In `logs\data-notes\` stehen die Codes `ServiceUnavailable` (Dienst fehlt) und `ServiceStaleFallback` (alte Daten verwendet), je Dienst mit Grund; `NvdUnavailable` entfällt.
- Der KI-Berater bekommt dieselben Angaben als `service_problems` (Code, Args, Text). Die Ampel bleibt unverändert.

### Sicherheitsprüfung: fehlende NVD-Daten sichtbar

- **Fehlt die NVD in einem Lauf, sagt die App das jetzt:** Hinweis oben in der Liste und eine Zeile in den Details („NVD nicht erreichbar, Ergebnis unvollständig“) mit Grund. Der Grund steht auch in `logs\data-notes\`. Vorher fielen solche Läufe nur dadurch auf, dass Lücken als „möglich“ erschienen, die die NVD längst ausschließt (Fall KeePass 2.61.1).
- An der einzelnen Lücke heißt es dann „NVD nicht erreichbar“ statt „Versionsbereich nicht auswertbar“.

### Portable Programme: Reste und ehrliche Meldungen

- **NSIS-Reste verschwinden aus der Liste.** `%TEMP%\~nsu*.tmp\Un_*.exe` ist die kurzzeitige Kopie eines Deinstallationsprogramms und kein Programm (Fall AnythingLLM). Andere Programme aus Temp bleiben sichtbar.
- **Portable Programme** bekommen statt „Deinstallieren“ den Knopf „Ordner öffnen“. Die falsche Meldung „nicht (mehr) installiert“ entfällt, solange die Datei noch da sein kann. „Aktualisieren“ verweist auf den Hersteller.
- **Nicht ausführbare Aktionen aus der App werden protokolliert,** wie es `docs/AKTIONEN.md` schon versprach. Bisher brach die Planung mit `-WhatIf` ohne Eintrag ab.

### Helfer: geschützte Kopie unter „Programme“

- **Liegt die App in einem beschreibbaren Ordner, startet sie erhöht nur noch eine geprüfte Kopie** unter `Program Files\Softwareverwaltung\Helper\<Version>\`. Damit schließt sich die Lücke, vor der die Bestätigung bisher nur gewarnt hat. Beim ersten Mal gibt es eine zusätzliche UAC-Abfrage für `robocopy` aus `System32`.
- **Geprüft wird die Kopie am Zielort:** Pfad, Ordnerrechte und im Release ausschließlich die Signatur. Nur Debug-Builds dürfen über den Hash anerkennen. Ohne Signatur bleibt es deshalb im Release bei der Warnung, bis die Signierung eingerichtet ist.
- **Austausch bei neuer Version nur durch die bereits geschützte Exe** und nur bei gültiger Signatur desselben Herausgebers. Ältere Versionsordner räumt die neue Exe beim nächsten Lauf auf.
- **„Kopie entfernen“** in den Einstellungen löscht den ganzen Helfer-Ordner.

### Updates: kein falsches „Erfolgreich“ mehr

- **Das Ergebnis zählt erst, wenn Windows Installer fertig ist.** winget kann Erfolg melden, während ein Installer im Hintergrund noch die alte Version entfernt. Bei der EA-App stand kurz die neue Version in der Liste, Sekunden später war das Programm weg, protokolliert war „Erfolgreich“. Jetzt wartet die App nach dem ersten Treffer höchstens 180 Sekunden auf das Ende der Transaktion und liest den Stand erneut. Ist das Programm dann weg oder fehlen alle bekannten Pfade, heißt das Ergebnis „Fehlgeschlagen“.
- **Sichtbar und abbrechbar:** Die Statuszeile zeigt „Warte auf Windows Installer …“, „Abbrechen“ beendet das Warten. Bleibt das Ergebnis offen, etwa weil Windows Update gerade installiert, bietet die App „Erneut prüfen“ an.
- **Warnung bei Paketen, die winget vor dem Update deinstalliert**, mit Link zum Hersteller; die Aktion bleibt möglich. Die EA-App steht dafür fest im Katalog. Für alle anderen Pakete gibt es den neuen Dienst „winget-Manifeste (GitHub)“, standardmäßig aus: Er ruft das Manifest der Zielversion ab, nur beim Bestätigen eines Updates.
- Nach einer abgelehnten UAC-Abfrage entfällt die Zeile „Kein Wiederherstellungspunkt“.

### Helfer für Administratorrechte als eigene Exe

- **Das PowerShell-Skript ist ersetzt** durch `lib\SoftwareInventory.Helper.exe` (C#, .NET Framework 4.7.2, Teil von Windows). Damit entfallen versteckte PowerShell, dynamischer Scriptblock und Base64-Plan auf der Kommandozeile, die Virenscanner gemeldet hatten. Der Plan kommt erst nach dem Handschlag über die Pipe.
- **Der Helfer prüft selbst, was er startet:** winget und `msiexec` nur in fester Form; Deinstallationsbefehle liest er aus dem Schlüssel unter HKLM und führt sie nur aus, wenn sie dem Plan entsprechen. Die DLL-Suche ist auf `System32` beschränkt.
- **Warnung im Bestätigungsdialog,** wenn der Helfer in einem für Benutzer beschreibbaren Ordner liegt. Das schließt die Lücke noch nicht; dafür folgt die geschützte Kopie unter `Program Files`.
- **Eigene Meldung `HelperFileMissing`,** wenn der Helfer fehlt, etwa nach einer Quarantäne.

### KI-Berater: Kennzeichnung als KI (AI Act Art. 50)

- Feste, nicht wegklickbare Zeile in der Seitenleiste, solange gefragt werden kann: Antworten erzeugt ein KI-Modell und können falsch sein. Jede Antwort trägt die Überschrift „KI-Berater (maschinell erzeugt)“, auch für Screenreader.

### Datenschutz und Rechtliches: Korrekturen aus der Durchsicht der Dokumentation

- **E-Mail-Adressen werden jetzt wirklich ersetzt** (`%EMAIL%`), bevor Text an den KI-Berater, in den Bericht oder in eine CPE-Meldung geht. `PRIVACY.md` versprach das schon, der Code tat es nicht. Paketangaben wie `lodash@4.17.21` bleiben erhalten.
- **Lizenz festgelegt:** `GPL-3.0-only`.
- **Doku berichtigt:** KI-Berater, Chat und Freigabestufen sind nicht mehr als geplant beschrieben. Das Nachinstallieren von winget und „Vorschlag melden“ stehen in der Liste der Verbindungen, CIRCL in den rechtlichen Hinweisen. Richtlinien für Firmen sind als geplant gekennzeichnet.

### Laufende Aktionen: Abbrechen, UAC-Anzeige, kein verlorener Abschluss (vor 4c-2)

- **Abbrechen ohne die App zu schließen**, für Einzelaktionen und die Warteschlange. Noch nicht gestartete Einträge verschwinden sofort. winget wird nur beendet, solange es noch keinen Installer gestartet hat. Ein laufender Installer wird nie beendet; die App zeigt dann „läuft im Hintergrund weiter, das Ergebnis wird nachgetragen“.
- **Eigene Phase für die UAC-Abfrage:** Die Statuszeile bat bisher während der ganzen Aktion um die Bestätigung, auch beim Download. Jetzt erscheint der Text nur, solange die Abfrage offen ist, mit Laufzeit und nach 30 Sekunden einem deutlichen Hinweis. Eine harte Zeitgrenze gibt es nicht, weil sich die Abfrage von außen nicht schließen lässt.
- **UAC-Abfrage mit dem Fenster der App als Besitzer** (`ElevationInterop` in der Native-DLL), damit sie vorne erscheint.
- **Handschlag mit dem Helfer:** Er startet erst nach dem `go` des Moduls. Wird die App bei offener Abfrage geschlossen, läuft auch nach einer späteren Bestätigung nichts mehr.
- **Warnung beim Schließen** auch bei Einzelaktionen. Das Schließen brach Updates nie ab, sie liefen unbeobachtet weiter und ihr Abschluss fehlte im Protokoll.
- **`Update-IncompleteActionLog`:** Beim Start werden solche Aktionen mit dem Ergebnis `Interrupted` nachgetragen (Praxisfall vom 07.11.: Visual Studio und CUDA).
- Die Ausgabe eines beendeten Programms wird nur noch begrenzt abgewartet; ein weiterlaufender Kindprozess kann den Helfer nicht mehr aufhalten.

### KI-Berater: Schutz gegen Endlosschleifen beim Denken (vor 4c-2)

- **`max_tokens` in jeder Anfrage**, einstellbar (`Advisor.MaxTokens`, Vorgabe 8192), und **Zeitgrenze je Anfrage einstellbar** (`Advisor.TimeoutSeconds`, Vorgabe 300 s, bisher fest). Beides auf der Einstellungsseite unter „KI-Berater“.
- **`finish_reason: "length"`** ergibt die eigene Meldung `AdvisorResponseTruncated` („Das Modell hat keine Antwort abgeschlossen …“, mit dem Tipp, Thinking auszuschalten oder die Presence Penalty zu erhöhen). Angefangene Tool-Aufrufe werden nicht ausgeführt, das Gespräch bleibt wie vor der Frage. Presence Penalty sendet die App nicht mit.
- Testfall aus der Praxis (07.11.): zwei Tool-Runden in Ordnung, danach Schleife beim Denken; bisher Abbruch erst nach 300 s mit `AdvisorTimeout`.

### Korrekturen (Hinweis zur Freigabestufe)

- Der einmalige Hinweis zur übernommenen Freigabestufe ließ sich nicht schließen: Der Knopf blieb nach dem Laden der Einstellungen grau, weil sein Befehl nach dem Ende des Ladens nicht neu bewertet wurde. Jetzt schließt ein ✕ rechts oben („Hinweis schließen“) den Hinweis in den Einstellungen und im Hauptfenster, ohne weiteres Zutun nur für diese Sitzung. Mit dem Haken „Nicht mehr anzeigen“ wird das Schließen sofort gespeichert und gilt auch nach einem Neustart.

### Weniger Schreibvorgänge im Zwischenspeicher (Etappe A, vor 4c-2)

- **Index je Programm** wird in `Get-SecurityRating` einmal am Ende geschrieben (Versions- und Lückenprüfung zusammen) und nur, wenn sich der Inhalt ändert. Bisher schrieb jeder Scan jede Index-Datei zweimal neu, auch unverändert.
- **EPSS je CVE in einer Datei** (`cache\EPSS\scores.json`) statt einer Datei je Sammelabfrage, deren Name die CVE-Liste war (jede neue CVE ließ eine Datei verwaisen). Abgefragt werden nur fehlende oder abgelaufene CVEs; „Geprüft vor …“ zeigt das tatsächliche Alter der EPSS-Werte. Eine unlesbare Datei gilt als leer, mit Eintrag im Fehlerprotokoll und ohne Meldung.
- **Messung** mit nachgebildeten Diensten (3 Programme): Ein zweiter Scan innerhalb der Haltbarkeit schreibt jetzt 0 Dateien statt 3 (je zweimal); eine neue CVE schreibt die EPSS-Datei einmal neu statt eine weitere anzulegen.
- Neues Fehlerprotokoll des Moduls für Fälle ohne Meldung (`logs\app-errors-<Datum>.log`, dieselbe Datei wie die App).

### Windows-Zugriff ohne Add-Type (vor 4c-2)

- **Fertig übersetzte DLL** `SoftwareInventory.Native.dll` im Modul (`lib\`, geladen über `RequiredAssemblies`) für die Anmeldeinformationsverwaltung und die Prüfung der Pipe-Gegenstelle bei Aktionen mit Administratorrechten. Bisher übersetzte das Modul diesen Code zur Laufzeit mit `Add-Type`; das ist im Constrained Language Mode (AppLocker/WDAC) gesperrt, lässt sich nicht signieren und kann Verhaltensschutz-Programme auslösen. Keine neuen Pakete.
- Zu lange Schlüssel (über 1280 Zeichen) lehnt `Set-ServiceCredential` jetzt mit Text aus der Sprachdatei ab (`ErrorSecretTooLong`).

### KI-Berater: Chat-Seitenleiste (Etappe 4c-1)

- **Seitenleiste „KI-Berater“** rechts im Hauptfenster, ein- und ausblendbar und in der Breite ziehbar (gemerkt in `app-ui.json`). Fragen mit Eingabetaste, „Abbrechen“, „Neues Gespräch“; Hinweise, wenn der Berater aus ist (mit „Einstellungen öffnen“) oder noch nicht gescannt wurde.
- **Antworten als reiner Text** ohne Markdown und ohne klickbare Links, darunter die Zeile „Abgefragt: …“ mit den aufgerufenen Tools.
- **Gegenseitige Sperre:** kein Fragen während Scan oder Aktion, kein Scan und keine Aktion während einer Antwort.
- **Gespräch nur im Speicher**, ab 20 Fragen fallen die ältesten Runden weg; es endet mit „Neues Gespräch“, beim Beenden und wenn sich gespeicherte Beraterwerte ändern.

### Korrekturen (4c-1)

- Die App schrieb `app-ui.json` und ihr Fehlerprotokoll immer in die Windows-Ordner, auch wenn `APPDATA`/`LOCALAPPDATA` umgelenkt waren (das Modul folgt den Umgebungsvariablen). Jetzt nutzen beide dieselben Ordner.
- Das Speichern der Detailfeld-Breite überschrieb andere Werte in `app-ui.json`.

### KI-Berater: Einstellungsseite (Etappe 4b-3)

- **Abschnitt „KI-Berater“** in den Einstellungen: einschalten (nur mit Adresse und Modell, `AdvisorIncomplete`), Server-Vorgabe, Adresse mit Hinweis „unverschlüsselt“, Modell (anfangs leer, kein Standardmodell) mit „Modelle laden“, API-Schlüssel, „Verbindung testen“.
- **Freigabestufe 0 bis 4** mit je einem Satz, was dazukommt, Hinweis bei Stufe 4 und aufklappbarer **Vorschau** der Daten, die das Modell auf der gewählten Stufe bekäme.
- **Einmaliger Hinweis** zur übernommenen Stufe 2 in den Einstellungen und, bei eingeschaltetem Berater, im Hauptfenster; weg nach „Verstanden“ oder einer gespeicherten Stufe.
- **Das Modul liest nie mehr selbst ein:** Ohne Daten aus einem Scan antworten die Tools mit `NoScanData`, statt still einen Scan mit Abfragen externer Dienste zu starten. Die Vorschau meldet dann `HasScanData = $false`.
- Beraterwerte gehen beim Speichern nur mit, wenn sie sich geändert haben; eine gespeicherte Adresse wird nicht bei jedem Speichern neu aufgelöst.

### Korrekturen (4b-3)

- `Set-AdvisorContext -Rating @()` speicherte bisher „keine Daten“ statt „Scan ohne Programme“ (PowerShell rollte das leere Array aus einem `if` ab).

### KI-Berater: Anbieter-Schnittstelle (Etappe 4b-2)

- **Anbieter-Schnittstelle in der App** (`IAdvisorProvider`) mit eigenen Typen für Nachrichten und Tools, damit externe Anbieter später als Plugin dazukommen. Erster Anbieter: `OpenAiCompatibleProvider` für lokale Server (`/models`, `/chat/completions` mit `tools`, ohne Streaming), ohne neue Pakete.
- **Prüfung beim Verbinden:** Die App löst den Namen selbst auf, verbindet nur zu geprüften lokalen Adressen und prüft die verbundene Gegenstelle; TLS prüft weiter gegen den Hostnamen. Kein Proxy, keine Weiterleitungen, Antworten höchstens 8 MB. Modul und App prüfen gegen dieselbe Tabelle mit Testfällen.
- **Gesprächsschleife** mit Tool-Aufrufen über das Modul, höchstens 8 Runden; die Freigabestufe folgt der Anbieterart. Fragen des Benutzers werden vor dem Senden bereinigt (`Protect-AdvisorText`).
- **Verbindungstest** (Adresse, Modelle, Tool-Aufruf ohne Inventardaten); fehlt nur der Tool-Aufruf, gibt es eine Warnung, speichern bleibt möglich. Bedienung folgt mit der Einstellungsseite (4b-3).
- **Neu im Modul:** `Get-AdvisorConnection` (Adresse, Modell, Schlüssel als `SecureString`) und `Protect-AdvisorText`. Nach jedem Scan übergibt die App die Bewertungen mit `Set-AdvisorContext`.

### KI-Berater: Freigabestufen (Etappe 4b-1)

- **Freigabestufen 0 bis 4 im Modul:** Die Tools geben nur die Felder der eingestellten Stufe zurück (Übersicht, Programmliste, Installationsdetails, portable Programme aus der Dateisuche, vergröberte Nutzungsspuren). Die Stufe bestimmt das Modul aus Anbieterart (`Invoke-AdvisorTool -ProviderKind Local|External`) und Einstellung `Advisor.ShareLevel`: lokal Voreinstellung 3, höchstens 4; extern (spätere Plugins) Voreinstellung 1, höchstens 3. Auf Stufe 0 gibt es nur eine Übersicht ohne Parameter (`ShareLevelTooLow` für alles andere).
- **Nie an die KI:** Pfad portabler Programme (nur die Art des Fundorts), Installationsdatum, genaue Zeitstempel, Startzähler, Art der Spur, Produktcodes, Registry-Schlüssel, Deinstallationsbefehle, Hash. „Zuletzt genutzt“ nur grob, fehlende Spuren heißen „unbekannt“.
- **Ältere Einstellungen** bekommen lokal Stufe 2 und einen einmaligen Hinweis (`ShareLevelNoticePending`); höher stellt nur der Benutzer.
- **Nur lokale Server:** `Get-AdvisorEndpointCheck` prüft die aufgelöste Adresse (Loopback, private Netze, Link-Local). Öffentliche oder nicht auflösbare Adressen lehnt `Set-InventorySetting` ab (`AdvisorEndpointNotLocal`, `AdvisorEndpointUnresolvable`); http im privaten Netz mit Hinweis `AdvisorEndpointUnencrypted`.
- **Vorschau:** `Get-AdvisorDataPreview -Level n` zeigt das bereinigte JSON, das das Modell auf dieser Stufe bekäme.

### Plattformfilter

- **Lücken nur für andere Plattformen zählen unter Windows nicht:** Die NVD führt unter derselben CPE oft Lücken nur für macOS, iOS, Android oder Linux (UND-Konfiguration mit einem anderen Betriebssystem oder `target_sw` wie `android`), CIRCL ebenso (`platforms`, Produktnamen wie „Firefox for Android“). Solche Einträge zählen nicht mehr als Treffer; die Quelle meldet dann „nicht betroffen“ mit dem Grund „Nur für macOS, nicht für Windows“. Ausgeschlossen wird nur, was eindeutig einer bekannten anderen Plattform zugeordnet ist; Unbekanntes zählt weiter. Bei genau passendem CPE-Produkt schließt der Name nichts aus.
- **Widerspruch bleibt Gelb:** Meldet eine Quelle „nur andere Plattform“ und die andere „betroffen“, gilt „möglicherweise betroffen“ (`SourcesDisagree`).
- **KEV-Treffer nur für andere Plattformen widerlegt**, wenn alle NVD-Konfigurationen des Produkts eindeutig andere Plattformen betreffen (`KevRefutedPlatform`); sonst bleibt der Treffer.
- **Hinweis in den Details:** „2 Lücken betreffen nur andere Plattformen“ mit der Liste zum Aufklappen (CVE und Plattformen), ohne Wirkung auf die Ampel; ebenso im Bericht und für den KI-Berater (`otherPlatform`).

### Ansicht der Details

- **Detailfeld über der Liste:** Ein Klick auf ein Programm (oder Eingabe) öffnet rechts ein Feld, das über der Liste liegt; die Liste behält ihre volle Breite. Ein Klick auf ein anderes Programm oder ↑/↓ wechseln den Inhalt, der Fokus bleibt in der Liste. Schließen mit ✕ oder Esc. Die Breite lässt sich am linken Rand ziehen (Start 40 %, mindestens 360 px) und wird in `%APPDATA%\SoftwareInventory\app-ui.json` gemerkt. Die aufgeklappte Zeile in der Liste entfällt.
- **Kompakte Lückenliste:** eine aufklappbare Zeile je CVE mit Bewertung, KEV, CVSS und einem Zeichen je Quelle (✓ betroffen, ✗ nicht betroffen, ? nicht auswertbar, – nicht bekannt); aufgeklappt EPSS, jede Quelle mit Bereich und Link, Beschreibung. Zeichenerklärung und Namensnennung (NVD; CVE-Programm über CIRCL, CC BY 4.0) einmal unter der Liste. Höchstens drei Gründe sichtbar, der Rest zum Aufklappen. Reihenfolge: Aktionen, Gründe, Lücken, Programm, widerlegte Treffer, Verlauf.
- **Kein Scan mehr beim Start:** Ein Scan fragt externe Dienste ab und startet nur auf „Scannen“.

### Korrekturen

- **Ein einzelner Fehler verwarf den ganzen CIRCL-Abruf:** Bei großen Produkten (Chrome: rund 150 Seiten) begann der nächste Scan nach einem Netzwerk- oder Serverfehler wieder bei Seite 1. Jetzt wird jede Seite bei Netzwerkfehler, Zeitüberschreitung oder 5xx bis zu zweimal neu angefragt (nach 5 und 15 Sekunden, in der Anzeige sichtbar). Scheitert ein vollständiger Abruf trotzdem, steht er mit Seite und Fehler in `logs\data-notes` (Code `CirclFullFetchFailed`); ein halber Bestand wird weiterhin nie gespeichert.
- **Dauerschätzung für CIRCL zu hoch:** Die Seitenzahl wird jetzt mit etwa 48 KB Bestand je Seite geschätzt (vorher 34 KB; bei Chrome 40 % zu viele Seiten).
- **winget-Update meldete „Nicht (mehr) installiert“** (z. B. FFmpeg, `Gyan.FFmpeg`): winget findet manche Pakete mit `--id … --exact` nur über die lokale Kennung des installierten Eintrags (`ARP\User\X64\<Schlüssel>`), nicht über die angezeigte Katalog-ID. Der Plan prüft das jetzt nur lesend und nimmt dann die lokale Kennung, weiterhin mit `--exact`. Findet winget das Paket gar nicht genau, wird nichts ausgeführt und die Herstellerseite genannt. Meldet winget nach dem Start „nicht gefunden“, obwohl das Programm noch da ist, heißt das Ergebnis nicht mehr „nicht mehr installiert“.
- **Portable Programme verschwanden nach einer Einzelprüfung** („Das Programm ist nicht mehr installiert.“), z. B. nach „CPE zuordnen“, „Neu prüfen (ohne Cache)“ oder einer Aktion: `Find-InstalledSoftware` suchte nur im Inventar (Registry, winget, Store). Jetzt wird bei portablen Programmen die Datei neu gelesen; Nutzungsspuren bleiben. Fehlt die Datei, gilt das Programm als entfernt; ist ihr Laufwerk nicht verbunden, bleibt der bisherige Datensatz.

### Zwischenspeicher

- **NVD-Antworten verschlankt gespeichert:** nur ID, Datum, englische Beschreibung, CVSS und `configurations` (vollständig); gemessen 86 MB → 26 MB. Antworten ohne Lücken (CPE-Suche) bleiben unverändert.
- **Bereinigung nach Größe:** zuerst der Zwischenspeicher, dann die Logs (das Aktionsprotokoll bleibt so länger erhalten).
- **CIRCL-Bestände mit eigener Grenze** `CirclStoreMaxSizeMB` (Standard 200 MB, in der App unter Einstellungen), nicht mehr Teil von `LogMaxSizeMB`. Gelöscht werden sie nach Alter, über der eigenen Grenze (Ältestes zuerst) oder nach einem vollständigen Scan, in dem das Produkt nicht mehr vorkommt (`Remove-UnusedCirclStore`). Vorher räumte die allgemeine Grenze sie als Älteste zuerst ab; große Bestände wie Chrome mussten dann neu geladen werden.

### Zweite Quelle: CIRCL Vulnerability-Lookup

#### Neu

- **CIRCL als zweite Quelle für Sicherheitslücken** (Dienst `CIRCL`, standardmäßig aus, nur mit zugeordneter CPE). Gesendet werden nur Hersteller und Produkt, die Versionsangaben der CVE-Datensätze (CVE 5) wertet das Modul lokal aus: strukturierte Bereiche, einfache Textformen (`< 8.9.6.1`, `>= 9.11, < 26.01`) und feste englische Muster („Fixed in X“, „before X“, „prior to X“, „X and earlier“). Nicht auswertbare Angaben fallen unter die Altersregel.
- **Angabe je Quelle:** Jede Lücke erscheint einmal (gleiche CVE-ID) und nennt in `Sources` die Angabe von NVD und CIRCL einzeln mit Bereich, Namensnennung und Link. Die Details der App und der HTML-Bericht zeigen sie immer, auch wenn die Quellen übereinstimmen; bei CIRCL steht „Daten: CVE-Programm über CIRCL, CC BY 4.0“.
- **Widerspruch der Quellen:** Meldet eine Quelle „betroffen“ und die andere mit Versionsdaten „nicht betroffen“, gilt „möglicherweise betroffen“ mit Grund `SourcesDisagree` (Gelb). Ein Widerspruch widerlegt nie.
- Optionaler **CIRCL-Schlüssel** (Anmeldeinformationsverwaltung oder `CIRCL_API_KEY`), eigene Haltbarkeit `CacheHours.CIRCL` und Nutzungshinweis; in der App unter Einstellungen. Das Schlüsselfeld ist aus der App entfernt, weil der Schlüssel praktisch nichts beschleunigt; das Modul nutzt einen gespeicherten Schlüssel weiter. Zum Wiedereinhängen den Eintrag `new("CIRCL", …)` in `Credentials` (`SettingsViewModel.cs`) aus Commit `ac8f134` übernehmen; die Texte `SettingsCredentialCIRCL*` stehen noch in `Strings.resx`.
- Einstellungen: Die Grenzen heißen jetzt „Logs und Zwischenspeicher höchstens MB, ohne CIRCL-Bestände“ und „CIRCL-Bestände höchstens MB, eigene Grenze“.

#### Geändert

- **HTTP 429:** Mit `Retry-After` bis 60 Sekunden wartet das Modul einmal und wiederholt die Anfrage; sonst gilt wie bisher der veraltete Zwischenspeicher. Gilt für alle Dienste.
- Der User-Agent nennt die Projektadresse als Kontakt.
- `Get-RefreshEstimate` zählt CIRCL mit (`CirclEnabled`, `CirclRequests`, `CirclUnknown`): alle Seiten des vollständigen Abrufs, geschätzt aus der Größe des Bestands, und den Ablauf je CPE nacheinander statt nur der längeren Wartezeit. Auf einem PC mit gut 100 Programmen mit CPE ergibt das etwa 28 statt 3 Minuten.
- **CIRCL-Bestand mit Nachladen:** Je Produkt ein verschlankter Bestand (bei Chrome etwa 2 % der Antworten), danach nur Änderungen per `since=` statt alle 24 Stunden alles neu, wie es die Zugriffsregeln von CIRCL verlangen. Vollständig nur ohne lesbaren Bestand, nach 30 Tagen oder bei „Neu prüfen ohne Cache“. `Clear-CheckCache` behält den Bestand und lädt beim nächsten Mal nach. Ein abgebrochenes Nachladen setzt das Abrufdatum nicht weiter.
- **Fortschritt mit aktuellem Schritt:** Unter „Prüfe Sicherheitslücken (3 von 9): Programm“ zeigt die App eine zweite Zeile, z. B. „CIRCL: erster Abruf, Seite 37 von 149, noch etwa 6 Min. (danach aus dem Zwischenspeicher)“, „CIRCL: Änderungen seit …, Seite 1“, „NVD: Versionssuche“, „NVD: Abgleich mit CIRCL, Seite 2 von 3“ oder „… aus dem Zwischenspeicher“. Wartezeiten des Anfragelimits hängen an diesem Schritt („· Warte 3 s (Anfragelimit CIRCL)“), das Warten nach einem 429 steht in eigener Zeile.
- **Alter CIRCL-Zwischenspeicher:** Die einzelnen Suchseiten des alten Formats werden beim ersten Laden des Moduls einmalig gelöscht, mit Eintrag im Aktionsprotokoll (`CacheMigration`, Anzahl und MB). Bestände je Produkt bleiben.
- **Commit-Kennungen als Bereichsgrenze** (z. B. `>= 9a32b86…, < 8.0` bei CIRCL) sind keine Versionen: Sie fallen weg (Bereich dann `< 8.0`, lieber ein Fehlalarm mehr) und stehen im neuen Protokoll `logs\data-notes\<Datum>.jsonl` (Code `CommitVersionBound`, CVE, Produkt, Wert), damit sich solche Datensätze später finden lassen.
- Beschreibungen der Lücken ohne Zeilenumbrüche und Leerzeilen (NVD und CVE-Datensätze).
- **Gründe der Ampel:** Mehrere „möglicherweise betroffen“ stehen als ein Grund („8 Lücken möglicherweise betroffen (…)“, Code `PossiblyAffectedCount`); aktiv ausgenutzte (KEV) und Widersprüche der Quellen bleiben einzeln.
- **Rückfrage vor langem Scan ohne Cache:** auch mit NVD-Schlüssel, wenn die Schätzung über 5 Minuten liegt („Ein Scan ohne Zwischenspeicher dauert etwa 29 Minuten. Fortfahren?“); `Get-RefreshEstimate` liefert dazu `ConfirmReason` (`NvdWithoutKey`, `LongDuration`).
- Selbstbereinigung: Sind alle Dateien zu alt, räumt sie jetzt auch die leeren Ordner auf (vorher Abbruch beim Größenvergleich).
- `PRIVACY.md`, `THIRD-PARTY-NOTICES.md`, `docs/EXTERNE-DIENSTE.md`, `docs/SCHWACHSTELLEN.md` und `docs/TECHNIK.md` beschreiben CIRCL (Sitz Luxemburg, CC BY 4.0, Abfragegrenzen).

### CPE-Zuordnung

#### Neu

- **„CPE zuordnen“** in den Details für Programme ohne CPE (Grau mit Grund `NoCpe`): unbestätigte Vorschläge aus dem NVD-Wörterbuch mit Bewertung und Link zur NVD oder eigene Eingabe, geprüft wie in `Set-CpeMapping`. Ein Vorschlag füllt nur das Eingabefeld; gespeichert wird erst mit „Zuordnen“ (Standard-Button „Abbrechen“). Danach wird nur dieses Programm neu geprüft. Eigene Zuordnungen lassen sich dort ändern und entfernen.
- **„Vorschlag melden“** für eigene Zuordnungen: `Get-CpeMappingReport` baut den Link zu einem vorausgefüllten GitHub-Issue (Formular `.github/ISSUE_TEMPLATE/cpe-zuordnung.yml`), ohne Benutzer- und Rechnernamen. Die App zeigt den Inhalt vorher und öffnet den Browser erst nach Bestätigung; abgeschickt wird nur vom Benutzer selbst.
- **Katalog:** Jede CPE trägt einen Prüfvermerk `CpeCheck` (Datum, Belege, Notiz) nach dem Maßstab in `docs/KATALOG.md` („CPE prüfen“); `Test-CatalogEntry` verlangt ihn. Die bestehenden Einträge sind nachgeprüft.
- **Katalog erweitert:** 46 neue Einträge mit geprüfter CPE, u. a. Google Chrome, Microsoft Edge, Thunderbird, LibreOffice, GIMP, Node.js, .NET Runtime, Visual Studio Code und 2022, PuTTY, WinSCP, Wireshark, TeamViewer, NVIDIA-Grafiktreiber und CUDA Toolkit. Abgelehnte Kandidaten (Versionen nicht vergleichbar, anderes Produkt oder nicht im NVD-Wörterbuch) bekommen keine CPE und bleiben Grau mit Grund `NoCpe`.

#### Behoben

- **Audacity:** Die CPE `audacity:audacity` ist in der NVD veraltet und durch `audacityteam:audacity` ersetzt; Audacity wurde deshalb bisher nie auf Lücken geprüft.

#### Geändert

- `Find-CpeCandidate` bereinigt den Namen gründlicher (Architektur, Zusätze in Klammern, „release“/„stable“), sucht bei Bedarf mit dem Produktteil der winget-ID weiter, vergleicht alle aussagekräftigen Wörter des Herausgebers und nutzt Herstelleraliase (`Data/cpe-vendor-alias.json`). Veraltete CPEs und Treffer ohne Bezug zum Produkt werden nicht mehr vorgeschlagen. Neu in der Ausgabe: `Query` und `Url`.
- `Get-SoftwareVulnerability` liefert zusätzlich `CpeBase` (CPE ohne Version); die Details zeigen die CPE und ob sie vom Benutzer bestätigt ist.
- Der Grund `NoCpe` nennt den Weg über „CPE zuordnen“.

### Portable Suche: laufende Installer

#### Behoben

- Laufende Prozesse zählen nur noch als Spur eines portablen Programms, wenn die Datei auf `.exe` endet. Installer wie Inno Setup (`%TEMP%\is-*.tmp\Setup.tmp`) erschienen sonst als portables Programm. Ignorierte Prozesse stehen mit Pfad im Debug-Datenstrom (`-Debug`). Laufende `.exe` aus Temp bleiben in der Liste, mit dem Merkmal `InDownloadsOrTemp`.

### Store-Vereinbarung und Telemetrie

#### Geändert

- **Store-Pakete (`msstore`):** Die Vereinbarung der Store-Quelle wird nicht mehr still im Befehl akzeptiert. Vor der ersten Aktion zeigt die App sie einmal an (Standard-Button „Abbrechen“) und speichert die Zustimmung (`Set-InventorySetting -StoreAgreementAccepted`, Text über `Get-StoreAgreementNotice`). Ohne Zustimmung ist die Aktion nicht ausführbar, Grund `StoreAgreementRequired`; das gilt auch in der Warteschlange.
- **Telemetrie:** `POWERSHELL_TELEMETRY_OPTOUT=1` für die eingebettete PowerShell und den erhöhten Helfer; in `PRIVACY.md` und `docs/TECHNIK.md` beschrieben.

#### Behoben

- `Write-InventorySetting` hat die Zwischenspeicher-Dauern (`CacheHours`) nicht gespeichert. Jetzt werden alle Bereiche der Einstellungen gespeichert; ein Test prüft das.

### Dokumentation: Datenschutz, Lizenzen, Technik, Rechtliches

#### Neu

- `PRIVACY.md` (Datenschutz) im Hauptverzeichnis, `docs/TECHNIK.md` (Bestandteile, Datenablage, Netzwerkverbindungen), `docs/EXTERNE-DIENSTE.md` (was an welchen Dienst geht, Freigabestufen als Planung), `docs/RECHTLICHES.md` (Lizenz, Haftung, Bedingungen der Datenquellen) und `docs/FIRMENEINSATZ.md` (Checkliste für Unternehmen). Die Entwürfe vom 24.10.2026 sind auf den Stand vom 28.10.2026 gebracht.

#### Geändert

- `THIRD-PARTY-NOTICES.md` ist um Entwicklungswerkzeuge, aufgerufene Programme, Daten der Dienste, Pflichthinweise und Regeln für neue Abhängigkeiten erweitert.
- Das README verweist auf die neuen Dokumente.

### Mehrfachauswahl und Update-Warteschlange

#### Neu

- **Auswahl:** Häkchen in der Liste (nur bei verfügbarem Update) sowie „Alle mit Update auswählen“, „Auswahl aufheben“ und „Ausgewählte aktualisieren“.
- **Gemeinsame Bestätigung:** zeigt alle genauen Befehle aus der Planung (`Get-UpdateQueuePlan`), gruppiert nach mit und ohne Administratorrechte und nicht ausführbar. Unbestätigte Updates sind gekennzeichnet. Standard-Button ist „Abbrechen“.
- **`Invoke-UpdateQueue`:**
  - Erhöhte Einträge laufen zuerst in einem Helfer mit einer UAC-Abfrage, davor ein einziger Wiederherstellungspunkt. Danach folgen die übrigen.
  - Jeder Eintrag wird mit seinem bestätigten Befehl neu geprüft.
  - Fehler halten die Warteschlange nicht an. Jede Aktion wird protokolliert.
- **Warteschlangen-Leiste:** zeigt den Status je Eintrag und bei Fehlern den Grund. Sie bietet „Anhalten“, „Fortsetzen“ und „Abbrechen“; die laufende Aktion wird jeweils fertig. Danach werden nur die betroffenen Programme neu geprüft.
- **Stapelbetrieb des erhöhten Helfers:** Ergebnisse je Schritt und die Befehle `next`/`stop` laufen über die vorhandene Pipe.
- **App schließen während der Warteschlange:** erst eine Warnung (Standard „Abbrechen“). Die laufende Aktion wird fertig, der Rest wird abgebrochen und protokolliert.
- **Netzwerk-Exit-Codes** (z. B. `0x80072EE7`, Server nicht gefunden) haben verständliche Texte.
- **Planen** zeigt Fortschritt („Plane die Warteschlange (12 von 43)“).

#### Geändert

- „Ohne Cache scannen“ ist jetzt ein Schalter „Ohne Cache“ neben „Scannen“. Beim Einschalten kommt ohne NVD-Schlüssel die Rückfrage mit geschätzter Dauer, „Abbrechen“ stellt den Schalter zurück. Solange er an ist, steht ein Hinweis darunter.
- Die Einzelausführung ist in `Read-HelperRun` und `Complete-ActionResult` aufgeteilt, die Warteschlange nutzt dieselbe Auswertung.

### Zwischenspeicher für Online-Abfragen

#### Neu

- **Haltbarkeit je Quelle einstellbar:** neue Einstellung `CacheHours` (neueste Version 6 h, NVD, EPSS und KEV je 24 h, erlaubt 1–720 h). In der App steht sie unter „Zwischenspeicher für Online-Abfragen“.
- **Neu prüfen ohne Cache:** `-Refresh` für `Get-SecurityRating`, `Test-SoftwareUpdate` und `Get-SoftwareVulnerability`. Jede Antwort wird pro Lauf einmal frisch geholt, der KEV-Katalog also einmal.
  - In der App gibt es dafür „Ohne Cache scannen“ und in den Details „Neu prüfen (ohne Cache)“.
  - Ohne NVD-Schlüssel fragt die App vor dem Scan nach. Die Rückfrage nennt die geschätzte Dauer (`Get-RefreshEstimate`) und führt zum Beantragen eines Schlüssels. Mit Schlüssel startet der Scan ohne Rückfrage.
- **Spalte „Geprüft“:** zeigt z. B. „vor 2 h“, das Ältere von Versions- und Sicherheitsprüfung. Der Tooltip nennt beide Zeitpunkte.
- **Veraltete Daten:** Ist ein Dienst offline oder am Anfragelimit, gelten abgelaufene Einträge weiter (`CheckStale`). „Geprüft“ erscheint dann kursiv und abgeschwächt, mit Hinweis im Tooltip.
- **Gezielt verwerfen:** Ein Index je Programm und Version merkt sich die benutzten Einträge. `Clear-CheckCache` verwirft sie, die App ruft das nach jeder Aktion vor dem Neuprüfen auf.

#### Geändert

- GitHub-Antworten werden standardmäßig 6 statt 12 Stunden zwischengespeichert, die winget-Suche 6 statt 24 Stunden.

### Detailansicht: Installationsordner

#### Neu

- `Resolve-InstallLocation` ermittelt den Installationsordner mit Herkunft.
  - **Sicher:** Installer-Eintrag, App-Paket, Dateisuche.
  - **Vermutlich:** Programmsymbol, eigenes Deinstallationsprogramm, MSI-Komponenten. Abgeleitete Ordner zählen nur, wenn dort ein Programm liegt.
  - **Nie verwendet:** Zwischenspeicher des Installers, `msiexec` und Starter anderer Programme.
  - **Ohne Ergebnis:** Grund als Code (`LocationNotFound`, `LocationNoProgramExe`, `LocationOnlyInstallerCache`, `LocationNoData`).
- **Details der App:**
  - zeigen den vollen Pfad mit Herkunft oder „Ordner unbekannt“ mit Grund;
  - bieten „Ordner öffnen“ (nicht bei Store-Apps) und „Pfad kopieren“;
  - ermitteln den Ordner erst beim Aufklappen und merken ihn für die Sitzung.
- Die Details klappen mit „Schließen“, Esc oder einem zweiten Klick auf die Zeile zu.

#### Geändert

- Alle Textspalten der Liste zeigen den vollen Text als Tooltip und kürzen mit „…“.

### Zwischenetappe: Texte auslagern (Modul)

#### Geändert

- **Meldungen mit Code:** Gründe der Ampel, Gründe und Hinweise der Versions- und Sicherheitsprüfung, widerlegte KEV-Treffer und Meldungen der Aktionen sind Meldungen vom Typ `SoftwareInventory.Message` mit `Code`, `Args` und `Text`. Logik und Tests prüfen den Code, App und Bericht zeigen den Text, der KI-Berater bekommt alle drei Felder. Die Texte sind wortgleich geblieben.
- **Aktionsprotokoll:** Es speichert Code und Args. `Get-ActionLog` baut den Text in der Sprache der Oberfläche neu auf. Ältere Einträge mit reinem Text sind mit „(älterer Eintrag)“ gekennzeichnet.
- **Erhöhter Helfer:** Er liefert nur noch Codes, den Text bildet das Modul.
- **Weitere Texte in der psd1:** Warnungen, Fehler, Bestätigungstexte, Exit-Code-Meldungen, Hinweise zu den Nutzungsbedingungen, Prüfmeldungen des Katalogs und der HTML-Bericht stehen jetzt in `SoftwareInventory.Strings.psd1`. Der Bericht übernimmt Datumsformat und Sprachangabe aus der Sprache der Oberfläche.
- **Sprache:** Die eingebettete Engine läuft ausdrücklich in der UI-Sprache der App. Ohne Übersetzung gelten die deutschen Basistexte.
- **Fortschritt:** Die Statuszeile zeigt eigene Meldungen wie „Prüfe Sicherheitslücken (12 von 85): Programmname“. Die englischen Fortschrittsmeldungen von PowerShell bei Webabfragen und winget sind unterdrückt.
- **Dokumentation:** Neuer Abschnitt „Texte und Meldungen“ in `docs/ENTWICKLUNG.md`.

### Zwischenetappe: Texte auslagern (App)

#### Geändert

- Alle Texte der App stehen in `Resources/Strings.resx` (XAML über `{loc:Text …}`, C# über `AppText.Get`/`AppText.Format`). Status des Moduls (Aktionsergebnis, Wiederherstellungspunkt, Bewertung einer Lücke) werden über Schlüssel aus Präfix und Code übersetzt. Datum und Zahlen folgen der Kultur der Oberfläche. Übersetzt ist noch nichts.
- Tests prüfen, dass jeder benutzte Schlüssel und jeder bekannte Code einen Text hat und dass in XAML keine festen Texte mehr stehen.
- `CLAUDE.md`, Konzept und README: Regeln für Codes mit Text in der UI-Sprache, Übersetzungen später per KI (zuerst Englisch), neuer Abschnitt „Übersetzungen beitragen“.

### Wartung

#### Behoben

- Eingebettete Engine: `PSModulePath` enthält nur noch die mitgelieferten Module und die Windows-Module aus System32 (z. B. Appx). Vorher erbte sie den Pfad des startenden Prozesses und konnte Benutzermodule oder Module eines installierten PowerShell 7 laden. Dabei zeigte sich, dass `CimCmdlets` bisher aus einem installierten PowerShell 7 kam; die App lädt es jetzt aus der mitgelieferten DLL.
- Installer-Logs werden mit `System.IO.Compression` statt `Compress-Archive` gepackt (kein Modul-Autoload nötig).

#### Geändert

- `Get-CpeMapping` und `Remove-CpeMapping` stehen jeweils in einer eigenen Datei unter `Public/`.
- Analyzer-Befehl in README und `docs/ENTWICKLUNG.md` prüft nur `./src/SoftwareInventory`, nicht die Modulkopien in `bin`.
### Nachbesserung: Suche nach portablen Programmen

#### Behoben

- Die App suchte keine portablen Programme, obwohl Nutzungsspuren, Ordner und Laufwerke einstellbar waren. Neu: `Invoke-InventoryScan` liest die installierten Programme und sucht portable Programme nur, wenn Spuren, Ordner oder Laufwerke eingerichtet sind (ohne Warnung, wenn nicht; installierte Programme werden nicht doppelt gelesen). Die App scannt damit; portable Programme erscheinen mit Quelle „Portable“, die Details zeigen den Fundort.

#### Geändert

- Einstellungen: Abschnitt „Suche nach portablen Programmen“ neu aufgebaut. Hauptschalter „Nach portablen Programmen suchen“ (`Set-InventorySetting -PortableSearch`, standardmäßig aus, keine Vorlage schaltet ihn ein); erst wenn er an ist, ist der Rest aktiv, vorher ausgegraut. Direkt darunter als neutrale Info der Hinweis, dass installierte Programme unabhängig davon erfasst werden. Dann „Wo suchen“ als Entweder-oder (`FileScan.Mode`, `Set-InventorySetting -ScanMode Drives|Folders|None`), keine Option vorausgewählt: „Ganze Laufwerke“ (alle erkannten Laufwerke einzeln, auch Wechseldatenträger wie USB; mit Hinweis auf lange Dauer, sobald eines angehakt ist) oder „Nur bestimmte Ordner“ (Liste mit „Entfernen“ je Eintrag, „Ordner auswählen…“, Vorschläge `%USERPROFILE%` und Downloads; standardmäßig leer). Angezeigt und durchsucht wird nur die gewählte Option; die Auswahl der anderen bleibt gespeichert. Dann „Wie suchen“: Nutzungsspuren, Temp, Prüfsumme, Ausschlüsse. Wer vorher Spuren oder Ordner eingerichtet hatte, muss die Suche einmal einschalten; gespeicherte Ordner werden als „Nur bestimmte Ordner“ übernommen, sonst gespeicherte Laufwerke als „Ganze Laufwerke“.
- Unter dem Hauptschalter zwei eigene Schalter, beide standardmäßig aus (`-TraceSearch`, `-FileSearch`): „Nutzungsspuren“ (liest nur, was Windows schon notiert hat, durchsucht keine Laufwerke, findet Programme überall; die vier Spuren klappen erst auf, wenn er an ist) und „Dateisuche“ (darunter „Wo suchen“, Temp, Prüfsumme, Ausschlüsse). Beide wirken unabhängig voneinander.
- Laufwerke live: Die Liste folgt angesteckten und abgezogenen Laufwerken und USB-Sticks ohne Neustart (WM_DEVICECHANGE). Ein gespeichertes Laufwerk, das fehlt, steht als „nicht verbunden“ da, bleibt gespeichert und wird beim Scan mit Hinweis übersprungen (fehlende Ordner ebenso).
- Nutzungsspuren auf nicht erreichbare Pfade (z. B. abgezogener USB-Stick) erscheinen als Treffer mit Flag `PathUnreachable` und dem Grund „Pfad nicht erreichbar“, statt verworfen zu werden. Spuren auf gelöschte Dateien eines vorhandenen Laufwerks werden weiter verworfen.
- Datenschutz: Der eigene Name in Pfaden auf anderen Laufwerken (z. B. `F:\Users\<Name>` auf USB) wird zu `%USERNAME%`. Tests für Pfade auf Wechseldatenträgern, nicht erreichbaren Laufwerken und Netzpfaden. Die Berater-Tools geben keine Nutzungsspuren weiter (keine Zeitstempel, Startzähler, Spurenart); die geplanten Freigabestufen sind noch nicht umgesetzt.
- Ohne gewählte Option oder mit leerer Liste der gewählten Option läuft kein Dateiscan; Nutzungsspuren wirken unabhängig davon. Die Einstellungsseite zeigt das als Hinweis, der Scan meldet es ebenfalls (Text in den Modultexten). Auch `Get-PortableSoftware` ohne Parameter nutzt nur die aktive Option.
- Vorlagen setzen nur sichtbare Schalter, die Option „Wo suchen“ und nur deren Einträge, nie den Hauptschalter; die Statuszeile nennt jede Änderung (z. B. „Wo suchen: Nur bestimmte Ordner; Ordner: %USERPROFILE%“).
- App-Texte: Grundlage für `.resx` (`Resources/Strings.resx`, `{loc:Text Schlüssel}` in XAML, `AppText.Get` in C#) mit Test, dass jeder verwendete Schlüssel existiert. Die neuen Texte stehen schon dort.

### Etappe 4a: KI-Berater im Modul

#### Hinzugefügt

- Tools für den KI-Berater: `get_inventory`, `get_program_details`, `check_latest_version`, `search_vulnerabilities`, `propose_update`, `propose_uninstall`. `Get-AdvisorTool` beschreibt sie anbieterunabhängig (JSON-Schema) und liefert mit `-SystemPrompt` die Systemanweisung; `Invoke-AdvisorTool` prüft die Argumente und gibt bereinigtes JSON zurück, Fehler als Meldung für das Modell. Vorschläge führen nie etwas aus.
- `Set-AdvisorContext`: übergibt die Bewertungen des letzten Scans, damit nicht jede Frage einen Scan auslöst.
- `Protect-PrivateText`: gemeinsame Bereinigung für Berater und HTML-Bericht – eigenes Profil (auch in JSON und mit `/`), Profile anderer Benutzer, Benutzername, Rechnername, Domäne, API-Schlüssel.
- Einstellungen `Advisor` (Schalter, Vorgabe, Adresse, Modell; standardmäßig aus, kein Standardmodell) und `Get-AdvisorEndpointPreset` mit den Standardadressen von Ollama, LM Studio und Unsloth Studio sowie „Eigene Adresse“. Schlüssel für den KI-Server über `Set-ServiceCredential -Service Advisor`.
- Doku `docs/BERATER.md`.
- Mehrsprachigkeit vorbereitet: neue Texte des Moduls in `SoftwareInventory.Strings.psd1` (geladen mit `Import-LocalizedData`, abgerufen mit `Get-LocalizedString`, Basissprache Deutsch). Fehler und Status des Beraters als feste Codes (`error_code`, `status_code`). Der Platzhalter für fremde Benutzerprofile ist sprachneutral `%OTHERUSER%`. Ein Test prüft, dass jeder verwendete Text-Schlüssel existiert. Regel in CLAUDE.md; bestehende Texte folgen in einer eigenen Etappe.

#### Geändert

- Entscheidung: Etappe 4 nur mit lokalen Modellen über die OpenAI-kompatible Schnittstelle; externe Anbieter (z. B. Claude API) später als Plugin. CLAUDE.md, KONZEPT.md und README angepasst.

### Etappe 3c: Details und Aktions-Buttons

#### Hinzugefügt

- App: In der Detailansicht einer Zeile die Buttons „Aktualisieren“ (nur bei verfügbarem Update) und „Deinstallieren“. Vorher fragt die App das Modul mit `-WhatIf` und zeigt einen Bestätigungsdialog mit dem genauen Befehl, ob Administratorrechte nötig sind und ob ein Wiederherstellungspunkt angelegt wird. „Abbrechen“ ist Standard.
- Ausgeführt wird nur der bestätigte Befehl: neuer Parameter `-ConfirmedCommandLine` für `Update-Software` und `Uninstall-Software`. Weicht der neu ermittelte Befehl ab, wird nichts ausgeführt (`Cancelled`, protokolliert).
- Ergebnis-Karte nach jeder Aktion: Ergebnis im Klartext, Meldung, Wiederherstellungspunkt; bei Fehlschlag „Mit <Methode> versuchen“ (wieder mit eigener Bestätigung), bei `ManualUpdateRequired` der Herstellerlink.
- Nach einer Aktion wird nur dieses Programm neu geprüft (`Find-InstalledSoftware`, findet es auch nach einem MSI-Update mit neuem Registry-Schlüssel über die winget-ID); deinstallierte Programme verschwinden aus der Liste.
- Detailansicht: Installationsart und -bereich, winget-ID, Ort und die bisherigen Aktionen zu diesem Programm aus dem Aktionsprotokoll.
- `Install-WingetPackageManager`: installiert winget (App Installer) über `Repair-WinGetPackageManager -Latest` nur für das eigene Konto, mit Bestätigung und Protokoll (`Get-ActionLog -Action InstallWinget`). In der App als Button „winget installieren“ in der Hinweis-Karte, wenn winget fehlt.
- Während einer Aktion sind Scan und weitere Aktionen gesperrt; die Statuszeile sagt, wenn Windows nach Administratorrechten fragt.

### Etappe 3d: Nachtrag Ampel

#### Geändert

- KEV-Treffer werden widerlegt, wenn die NVD für die installierte Version keinen Befall meldet oder der Katalog eine Angabe „behoben ab“ (`KevFixed`) hat und die Version gleich oder neuer ist. Widerlegte Treffer stehen in `Refuted` und als Grund in der Ampel; sie färben nie. Ohne NVD bleibt die Ampel dann Grau (nicht vollständig geprüft), mit NVD Grün. 7-Zip: CVE-2025-0411 behoben ab 24.09.
- Ist die installierte Version älter als „behoben ab“, gilt sie ohne NVD als sicher betroffen (bei KEV Rot).
- App: Spalte „Lücken“ zählt auch „möglicherweise betroffen“ (z. B. „1 möglich“, „2 + 1 möglich“), auch wenn nicht vollständig geprüft wurde. Neue Spalte „Grund“ zeigt den ersten Grund direkt in der Liste. Ein Klick auf eine Zeile zeigt alle Gründe, die Lücken mit CVE-Link, Bewertung, KEV, CVSS, EPSS und Beschreibung sowie widerlegte Treffer.

### Etappe 3d: Einstellungen

#### Hinzugefügt

- `Set-ServiceCredential`, `Remove-ServiceCredential`, `Get-ServiceCredentialStatus`: NVD-Schlüssel und GitHub-Token in der Windows-Anmeldeinformationsverwaltung (nur aktueller Benutzer, ohne Zusatzpaket). Ein gespeicherter Schlüssel hat Vorrang vor `NVD_API_KEY`/`GITHUB_TOKEN`; der Status nennt nur „vorhanden“ und die Quelle, nie den Schlüssel. Maskiert werden Schlüssel aus beiden Ablagen.
- `Get-SettingPreset`: liefert die Werte der Vorlagen „Quick“ und „Thorough“, ohne zu speichern. `Set-InventorySetting -Preset` nutzt dieselbe Funktion.
- App: Reiter „Programme“ und „Einstellungen“. Die Einstellungsseite zeigt alle Quellen, Nutzungsspuren, den Dateiscan (Ordner, Laufwerke, Temp, Hash, Ausschlüsse), externe Dienste mit Angabe, was gesendet wird, API-Schlüssel, Wiederherstellungspunkt und die Grenzen für Logs. Änderungen gelten erst nach „Speichern“, „Verwerfen“ stellt den gespeicherten Stand wieder her. Die Vorlagen belegen nur vor.
- Beim ersten Start fragt die App „Privat“ oder „Firma“ ab und zeigt danach die passenden Hinweise zu den Nutzungsbedingungen der externen Dienste. Es wird nichts eingeschaltet; alles bleibt aus und wird von Hand eingestellt. Die Hinweise stehen auch auf der Einstellungsseite.
- `Get-ServiceTermsNotice`: Kurzfassung der Nutzungsbedingungen von winget-Quellen, GitHub, NVD, CISA KEV und FIRST EPSS mit Link zum Original, bei „Firma“ mit Zusatzhinweisen. Ändert keine Einstellung.
- xUnit-Tests für die Einstellungsseite und für den Einstellungs-Service mit dem echten Modul (umgelenkte Einstellungsdatei, eigener Präfix in der Anmeldeinformationsverwaltung).

### Etappe 3b: WPF-Grundgerüst

#### Hinzugefügt

- WPF-App (.NET 10, Fluent-Design mit WPF-UI), folgt Hell/Dunkel und Akzentfarbe von Windows.
- Eingebettete PowerShell-Engine (`Microsoft.PowerShell.SDK` 7.6.9). Kern-Modul und das mitgelieferte `Microsoft.WinGet.Client` 1.29.380 werden mit vollem Pfad geladen; Ausführungsrichtlinie „Bypass“ nur für die eigene Sitzung. Aufrufe laufen im Hintergrund und sind abbrechbar.
- Hauptliste aus `Get-SoftwareInventory | Get-SecurityRating`: Ampel mit Text und Gründen, Name, Hersteller, installierte und neueste Version (mit „unbestätigt“), Zahl der Lücken (leer, wenn nicht geprüft), Quelle. Suche, Filter „Nur Updates verfügbar“ und „Nur Sicherheitsrisiken“.
- Hinweise oben im Fenster für Warnungen und Fehler des Moduls sowie für fehlendes winget, mit Link zu App Installer im Microsoft Store.
- `Test-WingetAvailability`: prüft winget.exe und das Modul `Microsoft.WinGet.Client` und beschreibt, was fehlt.
- Begleitpakete: Store-Pakete mit `AllowExternalContent` (Kontextmenü von WinMerge, Edge, OneDrive …) werden dem Programm unter `Companions` zugeordnet, wenn das eindeutig ist; sonst bleiben sie mit Flag `SparsePackage` stehen. Snapshot-Schema 3.
- `build/Publish-App.ps1`: self-contained für Windows x64, als Ordner und ZIP.
- `tests/Sandbox/Start-AppSandbox.ps1`: startet die veröffentlichte App in Windows Sandbox ohne .NET, PowerShell 7 und winget.
- `THIRD-PARTY-NOTICES.md` mit allen mitgelieferten Komponenten.
- xUnit-Tests für die eingebettete Engine, die Abbildung der Moduldaten und das ViewModel.

### Etappe 3a: Aktionen im Modul

#### Hinzugefügt

- `Update-Software`: aktualisiert über winget (`upgrade --id … --exact --source …`). Ohne winget-Paket wird nichts heruntergeladen, das Ergebnis enthält nur den Herstellerlink.
- `Uninstall-Software`: deinstalliert über winget, MSI (`msiexec /x {ProductCode} /qn /norestart /l*v`), Store-App, `QuietUninstallString` oder `UninstallString`. Wählbar mit `-Method`.
- `-WhatIf` liefert `Result = Planned` mit dem genauen Befehl, für den Bestätigungsdialog der App. `Uninstall-Software` fragt standardmäßig nach (ConfirmImpact High).
- Rückgabe als `SoftwareInventory.ActionResult` mit einheitlichem `Result`, Exit-Code, Zustand vorher und nachher, Wiederherstellungspunkt und nächster Methode.
- Erfolg wird geprüft: Der Eintrag muss weg bzw. die Version höher sein, sonst lautet das Ergebnis `NotVerified`.
- Adminrechte nur pro Aktion und nur für Programme des ganzen Rechners. Für Einträge unter HKCU und für Store-Apps gibt es nie Adminrechte. Bei unbekanntem Bereich fordert winget die UAC selbst an.
- Erhöhter Helfer für Windows PowerShell 5.1. Der Plan wird als Argument übergeben, das Skript per SHA256 geprüft. Das Ergebnis kommt über eine Named Pipe zurück, die nur erhöhte Clients öffnen dürfen; geprüft werden auch PID und Nonce.
- Befehle aus der Registry werden ohne Shell ausgeführt. Interpreter werden abgelehnt. Mit Adminrechten wird keine Datei gestartet, die der Benutzer verändern könnte.
- Optionaler Wiederherstellungspunkt (Einstellung `RestorePoint`, standardmäßig aus, oder `-CreateRestorePoint`). Er meldet `Created`, `Skipped`, `NotAvailable` oder `Failed` und bricht die Aktion nie ab.
- `Get-ActionLog`: Aktionsprotokoll als JSON-Zeilen unter `%LOCALAPPDATA%\SoftwareInventory\logs\actions`, mit Filtern. Beschädigte Zeilen werden übersprungen.
- Selbstbereinigung beim Laden des Moduls: Logs und Cache werden auf höchstens 30 Tage und 100 MB begrenzt, einstellbar mit `Set-InventorySetting -LogRetentionDays/-LogMaxSizeMB`. MSI-Logs werden nur bei Fehlern komprimiert aufgehoben.
- Integrationstest für Windows Sandbox (`tests/Sandbox`) mit festen Versionen und Prüfung von Hash und Signatur.

#### Behoben (gefunden im Sandbox-Test)

- MSI-Updates mit neuem ProductCode meldeten `NotVerified`, obwohl das Update geklappt hatte. Ist der alte Registry-Eintrag weg, zählt jetzt die Version laut winget.
- Läuft die App bereits mit Adminrechten (z. B. bei abgeschalteter UAC), galt jedes Programm unter „Programme“ als für Benutzer beschreibbar und wurde abgelehnt. Schreibrechte von Administratoren, SYSTEM und TrustedInstaller zählen nicht mehr.
- Programme des Benutzers (HKCU) liegen meist unter `AppData`. Der Helfer lehnt Benutzerordner jetzt nur noch ab, wenn er erhöht startet.
- Die Zustandsabfrage über winget nennt die Quelle. Vorher scheiterte sie ganz, sobald die Store-Quelle gestört war.

### Etappe 2c: Ampel und Bericht

- `Get-SecurityRating` (Rot, Gelb, Grün, Grau mit Grund) und `Export-SecurityReport` (HTML).

### Etappe 2b: Schwachstellen

- `Get-SoftwareVulnerability` mit NVD, CISA KEV und EPSS; CPE-Zuordnung über den Katalog (`Find-CpeCandidate`, `Set-CpeMapping`).

### Etappe 2a: Versionen

- `Test-SoftwareUpdate` und `Compare-SoftwareVersion`; neueste Version über winget, GitHub-Releases und winget-Suche; Produktkatalog.

### Etappe 1 und 1b: Inventar

- `Get-SoftwareInventory` (Registry, winget, Store-Apps), Snapshots (`Save-`, `Get-`, `Compare-InventorySnapshot`), `Get-PortableSoftware`, Einstellungen (`Get-`/`Set-InventorySetting`, alles standardmäßig aus).
