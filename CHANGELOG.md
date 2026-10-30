# Änderungen

Format nach [Keep a Changelog](https://keepachangelog.com/de/1.1.0/). Das Projekt ist noch nicht veröffentlicht; die Einträge sind nach Etappen gegliedert.

## Unveröffentlicht

### Korrekturen

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
- Optionaler **CIRCL-Schlüssel** (Anmeldeinformationsverwaltung oder `CIRCL_API_KEY`), eigene Haltbarkeit `CacheHours.CIRCL` und Nutzungshinweis; in der App unter Einstellungen.

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
