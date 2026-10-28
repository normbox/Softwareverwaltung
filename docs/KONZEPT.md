# Konzept: Software-Inventar & Update-Berater für Windows

Stand: 24.10.2026

## Ziel

Ein Open-Source-Werkzeug für Windows, das installierte Software erfasst, veraltete und unsichere Versionen markiert, per Klick aktualisiert oder deinstalliert und mit einem KI-Berater erklärt, was zuerst zu tun ist.

| Punkt | Festlegung |
| --- | --- |
| Einsatz | Zuerst privat auf einem PC, später Firmeneinsatz mit mehreren Rechnern |
| Plattform | Nur Windows 10/11. Linux wäre ein eigenes Projekt. |
| Lizenz | GPLv3 (entschieden 24.10.2026) |
| KI | lokal über die OpenAI-kompatible Schnittstelle (Ollama, LM Studio, Unsloth Studio); externe Anbieter später als Plugin |
| Oberfläche | .NET 10 WPF mit Fluent-Design (Bibliothek WPF-UI) |
| Pflege | So gering wie möglich: wenige Abhängigkeiten, Langzeitversionen |

Abgrenzung (entschieden 24.10.2026): Updates und Deinstallation löst UniGetUI (MIT) bereits gut. Dieses Projekt baut keine eigene Paketverwaltung nach, sondern nutzt winget für Aktionen. Schwerpunkt und Alleinstellung: Sicherheitsampel (CVE, KEV, EPSS), Erfassung portabler Programme, KI-Berater.

Leitsatz: Die Logik lebt in einem PowerShell-Modul, das auch ohne Oberfläche läuft. GUI, KI-Berater und ein optionaler MCP-Server sind nur Zugänge dazu.

## Architektur

```
 Desktop-App (WPF)        KI-Berater                 MCP-Server (optional)
 Liste, Ampel, Buttons    lokal (OpenAI-kompatibel)  für Claude Desktop u. a.
        |                        | Tool-Aufrufe              | Tool-Aufrufe
        v                        v                           v
 +--------------------- PowerShell-Modul (Kern) ----------------------+
 |  Inventar  |  Versionsabgleich  |  Sicherheitsprüfung  |  Aktionen  |
 +-----|-------------|---------------------|--------------------|-----+
       v             v                     v                    v
   Windows       Versionsquellen      Schwachstellen        Ausführung
   Registry,     winget, GitHub,      NVD, CISA KEV,        winget, msiexec,
   winget, Appx  Herstellerregeln     EPSS, OSV             Appx (mit UAC)
```

Die App bettet die PowerShell-Engine über das NuGet-Paket `Microsoft.PowerShell.SDK` ein; PowerShell 7 muss beim Nutzer nicht separat installiert sein. Scans, Cache und Protokoll werden lokal als JSON gespeichert.

## Inventarisierung

| Quelle | Liefert | Lücke |
| --- | --- | --- |
| Registry `HKLM\...\Uninstall` (64-Bit und `WOW6432Node`) | Name, Version, Hersteller, Pfad, Deinstallationsbefehl | Rauschen durch Updates und Treiber |
| Registry `HKCU\...\Uninstall` | Benutzer-Installationen | Nur aktueller Benutzer |
| `winget list` / WinGet-PowerShell-Modul | Paket-ID, verfügbare Version | Nicht jedes Programm zugeordnet |
| `Get-AppxPackage` | Store- und MSIX-Apps | Systemkomponenten ausfiltern |

Treffer werden zu einem Datensatz pro Programm zusammengeführt (Name, Hersteller, installierte Version, Quelle, winget-ID, Deinstallationsbefehl, Installationsart MSI/EXE/MSIX/winget, Bereich Rechner/Benutzer). Scans werden mit Zeitstempel gespeichert, damit Unterschiede sichtbar werden.

### Portable und nicht registrierte Programme

Programme ohne Installation stehen in keiner Uninstall-Liste. Sie werden über Ausführungsspuren, laufende Prozesse samt Autostart und einen gezielten Dateiscan gefunden.

| Weg | Findet | Rechte |
| --- | --- | --- |
| Amcache (`C:\Windows\AppCompat\Programs\Amcache.hve`) | Fast jede ausgeführte .exe mit Pfad, Version, Hersteller, SHA1 | Admin |
| BAM (`HKLM\SYSTEM\...\Services\bam\State\UserSettings`) | Letzte Ausführung je Benutzer | Admin |
| UserAssist (`HKCU\...\Explorer\UserAssist`, ROT13) | Per Explorer gestartete Programme, Startanzahl | Benutzer |
| Prefetch (`C:\Windows\Prefetch`) | Jüngere Ausführungen | Admin |
| `Get-Process` | Laufende Programme | Benutzer |
| Run-Schlüssel, Autostart-Ordner, geplante Aufgaben, Dienste | Dauerhaft mitlaufende Programme | teils Admin |
| Dateiscan gewählter Ordner (Downloads, Desktop, Dokumente, `%LOCALAPPDATA%`, `C:\Tools`) | Nie gestartete, herumliegende .exe | Benutzer |

Erkennung über die PE-Versionsinformationen der .exe (ohne Ausführen), dann derselbe Versions- und Sicherheitsabgleich. Zusätzlich Signaturprüfung (`Get-AuthenticodeSignature`) und SHA256-Hash.

Eigens markierte Warnsignale: veraltete Version mit Lücke ohne Installation, fehlende/ungültige Signatur (besonders in Downloads/Temp), Autostart oder Dienst ohne bewusste Nutzung seit Monaten, mehrere Kopien in verschiedenen Versionen.

Optional: Hash-Abgleich mit VirusTotal (eigener API-Schlüssel, nur Hash, nur nach Zustimmung). Noch nicht abgedeckt: veraltete Bibliotheken innerhalb von Programmordnern (späterer Ausbau). Der Tiefenscan braucht Admin-Rechte und wird bewusst mit UAC gestartet.

## Versionsabgleich

Austauschbare Provider in fester Reihenfolge, der erste Treffer gewinnt:

1. **winget** (`winget upgrade`, `Find-WinGetPackage`)
2. **GitHub Releases** (`/repos/{owner}/{repo}/releases/latest`; ohne Token 60, mit Token 5.000 Anfragen/Stunde)
3. **Herstellerregeln**: kleine Regeldateien je Produkt (URL + Versionsmuster oder Update-Feed) als Community-Katalog im Repository
4. **KI-Recherche** als Fallback, Ergebnis als „unbestätigt“ markiert

Versionen werden normalisiert verglichen (`24.08` = `24.8.0.0`), Ergebnisse zwischengespeichert.

## Sicherheitsprüfung

| Quelle | Zweck |
| --- | --- |
| NVD CVE-API 2.0 | CVEs je Produkt/Version über CPE, CVSS (kostenloser API-Schlüssel) |
| CISA KEV | Aktiv ausgenutzte Lücken, täglich laden, höchste Priorität |
| EPSS | Ausnutzungswahrscheinlichkeit für die Priorisierung |
| OSV, GitHub Security Advisories | Open-Source- und GitHub-Projekte |

Zuordnung Programm → CPE: gepflegtes Mapping im Repository, dann Suche im NVD-CPE-Wörterbuch, bei Unsicherheit Vorschlag des KI-Beraters mit Bestätigung durch den Nutzer.

Ampel: Rot bei KEV-Treffer oder kritischem CVSS, Gelb bei bekannten Lücken oder veralteter Version, Grün sonst.

## KI-Berater

Das Modell ruft Modulfunktionen als Tools auf und erklärt die Ergebnisse. Es führt nie selbst etwas aus.

| Tool | Wirkung | Freigabe |
| --- | --- | --- |
| `get_inventory` | Erfasste Software aus dem letzten Scan, filterbar | – |
| `get_program_details` | Gründe der Ampel, Lücken, widerlegte Treffer | – |
| `check_latest_version` | Neueste Version über die aktivierten Dienste | – |
| `search_vulnerabilities` | CVE-, KEV-, EPSS-Daten über die aktivierten Dienste | – |
| `web_search` / `fetch_page` | Recherche bei Unbekanntem (später) | Ergebnis unbestätigt |
| `propose_update` | Update vorschlagen | Nutzer bestätigt per Button |
| `propose_uninstall` | Deinstallation vorschlagen | Nutzer bestätigt per Button |

Entschieden 26.10.2026: Etappe 4 nur lokal. Die App spricht lokale Server über die OpenAI-kompatible Schnittstelle an (`/v1/chat/completions` mit `tools`). Vorgaben: Ollama (`http://localhost:11434/v1`), LM Studio (`http://localhost:1234/v1`), Unsloth Studio (`http://localhost:8888/v1`, mit API-Schlüssel) und eine eigene Adresse; kein Standardmodell, Auswahl aus den installierten Modellen. AnythingLLM fehlt vorerst, weil seine OpenAI-Schnittstelle `tools` nicht weitergibt. Externe Anbieter (z. B. Claude API) kommen später als Plugin über die Anbieter-Schnittstelle der App. Daten werden vor dem Senden immer bereinigt, auch für lokale Modelle (Benutzername, Rechnername, Domäne, Benutzerpfade, API-Schlüssel); die Einstellungen zeigen, was übertragen wird.

## Oberfläche und Aktionen

- **Hauptansicht:** Tabelle mit Ampel, installierter/neuester Version, Quelle, Buttons „Aktualisieren“ und „Deinstallieren“; Filter „Updates verfügbar“, „Sicherheitsrisiko“.
- **Detailansicht:** CVEs in einfachen Worten, Herstellerlink, Versionsverlauf.
- **Berater-Seitenleiste:** Chat; Vorschläge als Karten mit Bestätigungsbutton.
- **Update:** `winget upgrade --id`, sonst Herstellerlink.
- **Deinstallation:** `winget uninstall`, sonst Registry-Befehl (MSI per `msiexec /x`), Store-Apps per `Remove-AppxPackage`.
- **Vor jeder Aktion:** Bestätigung, optional Wiederherstellungspunkt, Protokolleintrag.
- **Rechte:** App läuft als normaler Benutzer, UAC nur für die einzelne Aktion.

## Entwicklungsumgebung

- .NET SDK 10: `winget install Microsoft.DotNet.SDK.10`
- VS Code mit „C# Dev Kit“: `code --install-extension ms-dotnettools.csdevkit`
- Git, Claude Code (VS-Code-Erweiterung)
- Optional: NVD-API-Schlüssel, GitHub-Token, ein lokaler KI-Server (Ollama, LM Studio oder Unsloth Studio)

## Fahrplan

1. **Inventar-Modul:** PowerShell-Modul liest Registry, winget, Store-Apps, schreibt JSON. Ohne Oberfläche testbar.
2. **Versions- und Sicherheitsprüfung:** winget- und GitHub-Provider, NVD- und KEV-Abgleich, Ampel; zunächst HTML-Bericht.
3. **Oberfläche:** WPF-App mit Liste, Details, Update- und Deinstallations-Buttons.
4. **KI-Berater:** Tools, lokale Modelle über die OpenAI-kompatible Schnittstelle, Anbieter-Schnittstelle für spätere Plugins, Chat-Seitenleiste. Vor 4b eine Zwischenetappe „Texte auslagern“: App-Texte nach `.resx`, Modulmeldungen nach `Import-LocalizedData`, Gründe und Status als Codes (Modul liefert `Code`, `Args` und `Text` in der UI-Sprache der App); noch keine Übersetzung.
   - **Übersetzungen:** entstehen später per KI, zuerst Englisch. Eine Prüfung durch Muttersprachler ist ausdrücklich erwünscht (README, Abschnitt „Übersetzungen beitragen“). Zum ersten Release gibt es die README auf Deutsch und Englisch.
5. **Ausbau:** Herstellerkatalog, MCP-Server, geplante Scans mit Benachrichtigung.
6. **Firmentauglich:** Zentrale Sammlung mehrerer PCs, Richtlinien, signierte Skripte.

## Offen

- Endgültiger Projektname (Repo vorerst: github.com/normbox/Softwareverwaltung)
- Plugin-Format für externe KI-Anbieter (Laden, Signaturprüfung)
