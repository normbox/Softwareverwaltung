# Drittkomponenten und Lizenzen

Stand: 24.10.2026

Softwareverwaltung steht unter der **GNU General Public License v3.0** (siehe [LICENSE](LICENSE)). Es nutzt Komponenten und Daten Dritter, die unter eigenen Lizenzen stehen. Diese Datei listet sie auf und enthält die geforderten Hinweise.

> **Keine Rechtsberatung.** Die Einschätzungen zur Lizenzverträglichkeit sind sorgfältig recherchiert, ersetzen aber keine anwaltliche Prüfung. Maßgeblich sind immer die Lizenztexte der jeweiligen Projekte in der verwendeten Version.

Legende Status: **genutzt** = im Code verwendet · **geplant** = laut Konzept vorgesehen · **nur Entwicklung** = wird nicht mit der App ausgeliefert.

## 1. Mitgelieferte Software (wird mit der App verteilt)

| Komponente | Zweck | Lizenz | Mit GPLv3 vereinbar | Status |
| --- | --- | --- | --- | --- |
| .NET 10 Runtime inkl. WPF (Microsoft) | Laufzeit, self-contained | MIT | ja | geplant |
| Microsoft.PowerShell.SDK (Microsoft) | eingebettete PowerShell-Engine | MIT | ja | geplant |
| Abhängigkeiten von Microsoft.PowerShell.SDK, u. a. Newtonsoft.Json, JsonSchema.Net, Humanizer, Microsoft.CodeAnalysis, Microsoft.ApplicationInsights, Markdig | Teil der Engine | überwiegend MIT, Markdig BSD-2-Clause | ja | geplant |
| WPF-UI (lepoco) | Fluent-Design-Oberfläche | MIT | ja | geplant |
| Microsoft.WinGet.Client (Microsoft) | winget-Daten und -Aktionen (dünne Hülle um die winget-COM-Schnittstelle) | MIT (Quellcode im Repository microsoft/winget-cli unter `src/PowerShell`); enthält weitere Komponenten laut `NOTICE` des Repositorys | ja | genutzt (Entwicklung), Mitliefern geplant |
| Anthropic C#-SDK (NuGet `Anthropic`) | Claude API | Apache-2.0 | ja (nur mit GPLv3, nicht GPLv2) | geplant, Wahl offen |
| Ollama-Client (z. B. OllamaSharp) oder eigener HTTP-Aufruf | lokale KI | OllamaSharp: MIT | ja | geplant, Wahl offen |

Hinweise:

- **PowerShell und .NET** liefern eigene Hinweisdateien (`ThirdPartyNotices.txt` bzw. `THIRD-PARTY-NOTICES.TXT`). Sie werden unverändert mit jedem Release ausgeliefert.
- **Microsoft.WinGet.Client** (geklärt 24.10.2026): Der Quellcode liegt im MIT-lizenzierten Repository microsoft/winget-cli; die Zeile „All rights reserved“ im Modulmanifest ist Microsofts übliche Copyright-Angabe und hebt die MIT-Lizenz nicht auf. Weitergabe ist erlaubt, wenn MIT-Lizenztext und die `NOTICE`-Datei beiliegen. Das Modul wird in fester Version im App-Ordner mitgeliefert und von dort geladen. Es enthält **nicht** winget selbst, sondern spricht die winget-COM-Schnittstelle des Windows-Pakets „App-Installer“ an (siehe [docs/TECHNIK.md](docs/TECHNIK.md#systemvoraussetzungen)).
- **Schriftarten:** Die Symbolschrift „Segoe Fluent Icons“ darf laut WPF-UI nicht mitgeliefert werden; unter Windows 11 ist sie vorhanden, unter Windows 10 muss sie fehlen oder ersetzt werden. Keine Windows-Schriften ins Repository oder Release legen.

## 2. Werkzeuge nur für die Entwicklung

Diese werden nicht verteilt; ihre Lizenz betrifft das Release nicht.

| Werkzeug | Zweck | Lizenz |
| --- | --- | --- |
| PowerShell 7.6 | Entwicklung, Tests | MIT |
| Pester | Unit- und Integrationstests | Apache-2.0 |
| PSScriptAnalyzer | statische Prüfung | MIT |
| .NET SDK 10 | Build | MIT |

## 3. Externe Programme (werden aufgerufen, nicht verteilt)

| Programm | Verwendung | Lizenz | Bemerkung |
| --- | --- | --- | --- |
| winget (Windows-Paket-Manager) | Abgleich, Update, Deinstallation | MIT (winget-cli) | Teil von Windows / App-Installer. Quellen haben eigene Bedingungen, siehe unten. |
| Windows-Bordmittel (`msiexec`, Appx-Cmdlets) | Deinstallation | Windows-Lizenz | Systembestandteile im Sinne von GPLv3 § 1 |
| Ollama / LM Studio | lokales Sprachmodell | Ollama: MIT; LM Studio: proprietär | Eigenständiges Programm, Kommunikation über HTTP; keine Verknüpfung im Sinne der GPL. |
| Lokale Sprachmodelle (z. B. Llama, Qwen, Mistral, Gemma) | KI-Berater | jeweils eigene Lizenz (Apache-2.0, Llama Community License, Gemma Terms, …) | Werden nicht mitgeliefert. Nutzer wählt und lädt das Modell selbst; im Firmeneinsatz Lizenz des Modells prüfen. |

## 4. Daten und Dienste Dritter

Die App fragt diese Quellen ab oder lädt deren Daten. Daten werden nur zwischengespeichert, nicht im Repository verteilt. Werden Daten später doch mitgeliefert (z. B. ein vorbereiteter Katalog), gelten die Hinweispflichten in der rechten Spalte.

| Quelle | Lizenz / Bedingungen | Pflicht für dieses Projekt |
| --- | --- | --- |
| NVD (NIST) CVE-API 2.0 | NVD Terms of Use; Daten gemeinfrei (US-Regierung) | Hinweistext anzeigen (siehe unten); API-Schlüssel nicht weitergeben; Abfragegrenzen einhalten |
| CISA Known Exploited Vulnerabilities | CC0 1.0 | keine; Quellenangabe freiwillig |
| EPSS (FIRST.org) | frei nutzbar laut EPSS Usage Agreement | Quellenangabe „wo möglich“ |
| OSV.dev | Software Apache-2.0; Daten unter der Lizenz der jeweiligen Ursprungsdatenbank | Lizenz je Datensatz beachten, wenn Daten weitergegeben werden |
| GitHub Advisory Database | CC BY 4.0 | Namensnennung bei Weitergabe |
| GitHub REST API (Releases) | GitHub Terms of Service, API-Nutzungsregeln | Abfragegrenzen einhalten, eigenes Token des Nutzers |
| winget-Community-Quelle (microsoft/winget-pkgs) | Manifeste MIT | Bei Übernahme in den Herstellerkatalog: Copyright-Hinweis |
| Microsoft-Store-Quelle (`msstore`) | eigene Quellvereinbarung von Microsoft | Nutzer muss der Vereinbarung zustimmen; nicht stillschweigend mit `--accept-source-agreements` übergehen |
| Anthropic Claude API | Anthropic Commercial Terms, Usage Policy | eigener Schlüssel des Nutzers; siehe [docs/EXTERNE-DIENSTE.md](docs/EXTERNE-DIENSTE.md) |
| VirusTotal | VirusTotal Terms of Service; **öffentliche API nicht für kommerzielle Produkte und Geschäftsabläufe** | nur privat oder mit Premium-Lizenz; siehe EXTERNE-DIENSTE |

## 5. Pflicht-Hinweise

Diese Texte erscheinen in der App unter „Über“ und in der Detailansicht der Quellen:

> This product uses the NVD API but is not endorsed or certified by the NVD.

> Daten zu aktiv ausgenutzten Schwachstellen: CISA Known Exploited Vulnerabilities Catalog (CC0).

> Ausnutzungswahrscheinlichkeiten: EPSS, FIRST.org, https://www.first.org/epss

> Sicherheitshinweise zum Teil aus der GitHub Advisory Database (CC BY 4.0) und OSV.dev.

## 6. Lizenzverträglichkeit mit GPLv3 (Kurzfassung)

- **MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, CC0** sind mit GPLv3 vereinbar. Ihr Lizenztext und Copyright-Hinweis müssen mitgeliefert werden; dafür ist diese Datei samt den Hinweisdateien von .NET und PowerShell da.
- **Apache-2.0** ist nur mit GPL **v3** vereinbar, nicht mit v2. Deshalb nicht auf „GPLv2 only“ wechseln.
- **Nicht aufnehmen:** Bibliotheken unter proprietären Lizenzen ohne Weitergaberecht, unter „Non-Commercial“-Klauseln (z. B. CC BY-NC) oder unter Lizenzen mit Nutzungsbeschränkungen (z. B. viele „Responsible AI“-Lizenzen), weil sie den Freiheiten der GPL widersprechen.
- **Systembibliotheken** von Windows (Registry, COM, WinRT) fallen unter die Ausnahme für Systembestandteile (GPLv3 § 1) und sind unproblematisch.
- **Externe Dienste über HTTP** (Claude API, Ollama, NVD …) sind keine abgeleiteten Werke; für sie gelten deren Nutzungsbedingungen, nicht die GPL.

## 7. Regeln für neue Abhängigkeiten

1. Begründung im Pull Request (siehe CLAUDE.md: Pflegeaufwand gering halten).
2. Lizenz in der verwendeten Version prüfen und hier eintragen, bevor gemergt wird.
3. Erlaubt ohne Rückfrage: MIT, BSD, Apache-2.0, ISC, Zlib, CC0, MPL-2.0, LGPL. Alles andere vorher klären.
4. Vor jedem Release die Liste mit dem tatsächlichen Paketstand abgleichen, z. B. mit `dotnet list package --include-transitive` und einem Lizenzbericht-Werkzeug (etwa `nuget-license`).
