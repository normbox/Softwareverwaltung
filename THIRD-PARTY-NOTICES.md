# Komponenten von Drittanbietern

Die veröffentlichte App enthält die folgenden Komponenten. Sie stehen unter eigenen Lizenzen; die Softwareverwaltung selbst steht unter der GPLv3 (siehe `LICENSE`). Alle unten genannten Lizenzen sind mit der GPLv3 vereinbar.

| Komponente | Version | Zweck | Lizenz | Quelle |
| --- | --- | --- | --- | --- |
| .NET-Laufzeit und WPF | 10 | Laufzeit der App (self-contained mitgeliefert) | MIT | https://github.com/dotnet/runtime, https://github.com/dotnet/wpf |
| Microsoft.PowerShell.SDK | 7.6.9 | Eingebettete PowerShell-Engine für das Kern-Modul | MIT | https://github.com/PowerShell/PowerShell |
| WPF-UI | 4.3.0 | Fluent-Design der Oberfläche | MIT | https://github.com/lepoco/wpfui |
| CommunityToolkit.Mvvm | 8.4.2 | Datenbindung und Befehle (MVVM) | MIT | https://github.com/CommunityToolkit/dotnet |
| Microsoft.WinGet.Client | 1.29.380 | PowerShell-Modul für winget-Daten (Inventar, verfügbare Updates) | MIT | https://github.com/microsoft/winget-cli |

Microsoft.WinGet.Client wird beim Bauen in fester Version aus der PowerShell Gallery geladen und per SHA256 geprüft. Es bringt eigene Abhängigkeiten mit (u. a. Newtonsoft.Json, Octokit, Semver, alle MIT); deren Hinweise stehen in `Modules\Microsoft.WinGet.Client\1.29.380\NOTICE.txt`.

Die Lizenztexte der Pakete liegen in den jeweiligen Quell-Repositories. PowerShell bringt außerdem eigene Hinweise für seine Abhängigkeiten mit (`ThirdPartyNotices.txt` im PowerShell-Repository).

Nicht mitgeliefert, sondern beim Benutzer vorausgesetzt bzw. von Windows bereitgestellt: winget (App Installer) und Windows PowerShell 5.1 für den erhöhten Helfer.
