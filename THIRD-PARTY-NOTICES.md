# Drittkomponenten und Lizenzen

Stand: 28.10.2026

Softwareverwaltung steht unter der **GNU General Public License v3.0** (siehe [LICENSE](LICENSE)). Es nutzt Komponenten und Daten Dritter, die unter eigenen Lizenzen stehen. Diese Datei listet sie auf und enthält die geforderten Hinweise.

> **Keine Rechtsberatung.** Die Einschätzungen zur Lizenzverträglichkeit sind sorgfältig recherchiert, ersetzen aber keine anwaltliche Prüfung. Maßgeblich sind immer die Lizenztexte der jeweiligen Projekte in der verwendeten Version.

## 1. Mitgelieferte Software (wird mit der App verteilt)

| Komponente | Version | Zweck | Lizenz | Quelle |
| --- | --- | --- | --- | --- |
| .NET-Laufzeit und WPF | 10 | Laufzeit der App (self-contained mitgeliefert) | MIT | https://github.com/dotnet/runtime, https://github.com/dotnet/wpf |
| Microsoft.PowerShell.SDK | 7.6.9 | Eingebettete PowerShell-Engine für das Kern-Modul | MIT | https://github.com/PowerShell/PowerShell |
| WPF-UI | 4.3.0 | Fluent-Design der Oberfläche | MIT | https://github.com/lepoco/wpfui |
| CommunityToolkit.Mvvm | 8.4.2 | Datenbindung und Befehle (MVVM) | MIT | https://github.com/CommunityToolkit/dotnet |
| Microsoft.WinGet.Client | 1.29.380 | PowerShell-Modul für winget-Daten (Inventar, verfügbare Updates) | MIT | https://github.com/microsoft/winget-cli |

Alle oben genannten Lizenzen sind mit der GPLv3 vereinbar.

Hinweise:

- **PowerShell und .NET** bringen eigene Abhängigkeiten mit (u. a. Newtonsoft.Json, Markdig; überwiegend MIT, Markdig BSD-2-Clause) und eigene Hinweisdateien (`ThirdPartyNotices.txt` im PowerShell-Repository bzw. `THIRD-PARTY-NOTICES.TXT` von .NET). Sie gehören unverändert zu jedem Release.
- **Microsoft.WinGet.Client** wird beim Bauen in fester Version aus der PowerShell Gallery geladen und per SHA256 geprüft. Es liegt im App-Ordner und wird von dort geladen. Seine eigenen Abhängigkeiten (u. a. Newtonsoft.Json, Octokit, Semver, alle MIT) stehen in `Modules\Microsoft.WinGet.Client\1.29.380\NOTICE.txt`. Die Zeile „All rights reserved“ im Modulmanifest ist Microsofts übliche Copyright-Angabe und hebt die MIT-Lizenz nicht auf. Das Modul enthält **nicht** winget selbst, sondern spricht die winget-COM-Schnittstelle des Windows-Pakets „App-Installer“ an (siehe [docs/TECHNIK.md](docs/TECHNIK.md#systemvoraussetzungen)).
- **KI-Berater:** Die App spricht lokale Modellserver über deren OpenAI-kompatible HTTP-Schnittstelle direkt mit `HttpClient` an, ohne zusätzliche Bibliothek.
- **Schriftarten:** Die Symbolschrift „Segoe Fluent Icons“ darf laut WPF-UI nicht mitgeliefert werden; unter Windows 11 ist sie vorhanden. Keine Windows-Schriften ins Repository oder Release legen.

## 2. Werkzeuge nur für die Entwicklung

Diese werden nicht verteilt; ihre Lizenz betrifft das Release nicht.

| Werkzeug | Zweck | Lizenz |
| --- | --- | --- |
| PowerShell 7.6 | Entwicklung, Tests | MIT |
| Pester | Unit-Tests des Moduls | Apache-2.0 |
| PSScriptAnalyzer | statische Prüfung | MIT |
| .NET SDK 10 | Build | MIT |
| xUnit, Microsoft.NET.Test.Sdk, coverlet | Tests der App | Apache-2.0 bzw. MIT |

## 3. Externe Programme (werden aufgerufen, nicht verteilt)

| Programm | Verwendung | Lizenz | Bemerkung |
| --- | --- | --- | --- |
| winget (Windows-Paket-Manager) | Abgleich, Update, Deinstallation | MIT (winget-cli) | Teil von Windows / App-Installer. Die Quellen haben eigene Bedingungen, siehe unten. |
| Windows PowerShell 5.1 (`powershell.exe`) | erhöhter Helfer für Aktionen mit Administratorrechten | Windows-Lizenz | Systembestandteil im Sinne von GPLv3 § 1; das Helferskript wird vor dem Start per Hash geprüft |
| Windows-Bordmittel (`msiexec`, Appx-Cmdlets, Systemwiederherstellung) | Deinstallation, Wiederherstellungspunkt | Windows-Lizenz | Systembestandteile im Sinne von GPLv3 § 1 |
| Ollama, LM Studio, Unsloth Studio oder ein anderer OpenAI-kompatibler Server | lokales Sprachmodell für den KI-Berater | Ollama: MIT; LM Studio und Unsloth Studio: eigene Bedingungen | Eigenständige Programme, Kommunikation über HTTP; keine Verknüpfung im Sinne der GPL. |
| Lokale Sprachmodelle (z. B. Llama, Qwen, Mistral, Gemma) | KI-Berater | jeweils eigene Lizenz (Apache-2.0, Llama Community License, Gemma Terms, …) | Werden nicht mitgeliefert. Nutzer wählt und lädt das Modell selbst; im Firmeneinsatz Lizenz des Modells prüfen. |

## 4. Daten und Dienste Dritter

Die App fragt diese Quellen ab oder lädt deren Daten, nur wenn der Dienst eingeschaltet ist. Daten werden nur zwischengespeichert, nicht im Repository verteilt. Der Produktkatalog im Repository enthält nur Zuordnungen (Erkennungsmuster, CPE-Namen, GitHub-Repositorys), keine Daten dieser Dienste.

| Quelle | Lizenz / Bedingungen | Pflicht für dieses Projekt |
| --- | --- | --- |
| NVD (NIST) CVE- und CPE-API 2.0 | NVD Terms of Use; Daten gemeinfrei (US-Regierung) | Hinweistext anzeigen (siehe unten); API-Schlüssel nicht weitergeben; Abfragegrenzen einhalten |
| CISA Known Exploited Vulnerabilities | CC0 1.0 | keine; Quellenangabe freiwillig; Logo und Siegel der CISA nicht verwenden |
| EPSS (FIRST.org) | frei nutzbar laut EPSS Usage Agreement | Quellenangabe |
| GitHub REST API (Releases) | GitHub Terms of Service, API-Nutzungsregeln | Abfragegrenzen einhalten, eigenes Token des Nutzers |
| winget-Community-Quelle (microsoft/winget-pkgs) | Manifeste MIT; installierte Pakete unter ihrer eigenen Lizenz | Bei Übernahme von Manifestdaten in den Produktkatalog: Copyright-Hinweis |
| Microsoft-Store-Quelle (`msstore`) | eigene Quellvereinbarung von Microsoft | Die winget-Suche nutzt nur die Quelle `winget`. Updates und Deinstallationen laufen über die Quelle, aus der das Paket stammt; bei Store-Paketen ist das `msstore`, und der Befehl enthält `--accept-source-agreements`. **Offen:** Die Zustimmung zur Store-Vereinbarung soll vorher sichtbar erfolgen statt still im Befehl (eigener Fix). |

Geplante weitere Quellen (z. B. CIRCL Vulnerability-Lookup, Cloud-KI als Erweiterung) werden hier eingetragen, sobald sie umgesetzt sind.

## 5. Pflicht-Hinweise

In der App stehen bei den Hinweisen zu den Nutzungsbedingungen der Dienste (Einstellungen und erste Auswahl „Privat“/„Firma“) der NVD-Hinweis wörtlich und die Angaben zu KEV und EPSS sinngemäß. Eine eigene Seite „Über“ mit genau diesen Texten ist geplant.

> This product uses the NVD API but is not endorsed or certified by the NVD.

> Daten zu aktiv ausgenutzten Schwachstellen: CISA Known Exploited Vulnerabilities Catalog (CC0).

> Ausnutzungswahrscheinlichkeiten: EPSS, FIRST.org, https://www.first.org/epss

## 6. Lizenzverträglichkeit mit GPLv3 (Kurzfassung)

- **MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0, CC0** sind mit GPLv3 vereinbar. Ihr Lizenztext und Copyright-Hinweis müssen mitgeliefert werden; dafür ist diese Datei samt den Hinweisdateien von .NET, PowerShell und Microsoft.WinGet.Client da.
- **Apache-2.0** ist nur mit GPL **v3** vereinbar, nicht mit v2. Deshalb nicht auf „GPLv2 only“ wechseln.
- **Nicht aufnehmen:** Bibliotheken unter proprietären Lizenzen ohne Weitergaberecht, unter „Non-Commercial“-Klauseln (z. B. CC BY-NC) oder unter Lizenzen mit Nutzungsbeschränkungen (z. B. viele „Responsible AI“-Lizenzen), weil sie den Freiheiten der GPL widersprechen.
- **Systembestandteile** von Windows (Registry, COM, WinRT, Windows PowerShell 5.1) fallen unter die Ausnahme für Systembestandteile (GPLv3 § 1) und sind unproblematisch.
- **Externe Dienste über HTTP** (NVD, GitHub, lokale Modellserver …) sind keine abgeleiteten Werke; für sie gelten deren Nutzungsbedingungen, nicht die GPL.

## 7. Regeln für neue Abhängigkeiten

1. Begründung im Pull Request (siehe CLAUDE.md: Pflegeaufwand gering halten).
2. Lizenz in der verwendeten Version prüfen und hier eintragen, bevor gemergt wird.
3. Erlaubt ohne Rückfrage: MIT, BSD, Apache-2.0, ISC, Zlib, CC0, MPL-2.0, LGPL. Alles andere vorher klären.
4. Vor jedem Release die Liste mit dem tatsächlichen Paketstand abgleichen, z. B. mit `dotnet list package --include-transitive` und einem Lizenzbericht-Werkzeug (etwa `nuget-license`).
