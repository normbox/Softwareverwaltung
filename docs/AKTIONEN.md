# Aktualisieren und Deinstallieren

```powershell
$inventar = Get-SoftwareInventory
$inventar | Where-Object AvailableVersion | Update-Software -WhatIf        # zeigt den genauen Befehl, führt nichts aus
$inventar | Where-Object Name -eq 'Contoso Tool' | Uninstall-Software     # fragt nach (ConfirmImpact High)
Get-ActionLog -Last 10 | Format-Table StartedAt, Action, Name, Method, Elevated, Result
```

Beide Funktionen nehmen Datensätze aus `Get-SoftwareInventory` oder `Get-InventorySnapshot` entgegen, ebenso Objekte mit `.Record` (`Get-SecurityRating`, `Test-SoftwareUpdate`). Sie liefern je Programm ein `SoftwareInventory.ActionResult`.

## Grundsätze

- **Erst bestätigen, dann ausführen.** `-WhatIf` führt nichts aus und liefert ein Ergebnis mit `Result = Planned`. Darin stehen der genaue Befehl (`CommandLine`, `FilePath`, `Arguments`) und `Elevated`. Die App zeigt diese Angaben im Bestätigungsdialog. Die KI darf Aktionen nur vorschlagen.
- **Kein automatischer Ersatzweg.** Schlägt die gewählte Methode fehl, wird kein anderer Befehl ausgeführt, denn diesen hätte niemand bestätigt. `NextMethod` nennt die nächste mögliche Methode, ein neuer Aufruf mit `-Method` probiert sie aus.
- **Zustand neu lesen.** Werte aus dem übergebenen Datensatz werden nie blind übernommen. Registry, Store-Apps und winget werden zum Zeitpunkt der Aktion neu gelesen. Ein veränderter Snapshot kann so keinen fremden Befehl einschleusen. Ist das Programm nicht mehr da, lautet das Ergebnis `NotInstalled`, und es wird nichts ausgeführt.
- **Erfolg wird geprüft.** Ein Exit-Code 0 allein genügt nicht. Nach dem Ende prüft das Modul bis zu 60 Sekunden lang, ob der Eintrag verschwunden bzw. die Version gestiegen ist. Viele Deinstallationsprogramme starten einen Kindprozess und kehren sofort zurück.
- **Keine Downloads.** Updates laufen nur über winget. Ohne winget-Paket lautet das Ergebnis `ManualUpdateRequired` und `VendorUrl` nennt einen Herstellerlink. Der kommt aus `URLUpdateInfo` bzw. `URLInfoAbout` in der Registry oder von GitHub-Releases laut Katalog, nur `http`/`https`.

## Methoden

| Reihenfolge | Methode | Befehl |
| --- | --- | --- |
| 1 | `Winget` | `winget uninstall --id <Id> --exact --source <Quelle> --silent --accept-source-agreements --disable-interactivity [--scope user\|machine]` |
| 2 | `Msi` | `msiexec.exe /x {ProductCode} /qn /norestart /l*v <Log>` (Produkt-ID aus dem Schlüsselnamen, nur bei `WindowsInstaller=1`) |
| 3 | `Appx` | `Remove-AppxPackage -Package <PackageFullName>` |
| 4 | `QuietUninstallString` | aus der Registry |
| 5 | `UninstallString` | aus der Registry |

Aktualisieren: `winget upgrade --id <Id> --exact --source <Quelle> --silent --accept-source-agreements --disable-interactivity --accept-package-agreements`.

Pakete werden nur über die exakte winget-ID aus dem Scan angesprochen, nie über den Namen. winget wird mit vollem Pfad aus dem App-Installer-Paket (`%ProgramFiles%\WindowsApps\Microsoft.DesktopAppInstaller_…\winget.exe`) gestartet. Der übliche Alias in `%LOCALAPPDATA%` fehlt im Profil eines anderen Administratorkontos, und den Paketordner können nur Administratoren beschreiben.

Befehle aus der Registry werden ohne Shell gestartet, nie über `cmd /c` oder `Invoke-Expression`. Der Programmpfad wird herausgelöst, in Anführungszeichen oder als längster vorhandener `.exe`-Präfix. Der Rest bleibt unverändert als Argumentzeichenfolge. Programmnamen ohne Ordner (z. B. `MsiExec.exe`) werden nur in System32 gesucht. Interpreter (`cmd`, `powershell`, `pwsh`, `wscript`, `cscript`, `mshta`, `rundll32`, `regsvr32`, …) werden abgelehnt (`Unsupported`).

## Administratorrechte

Das Modul läuft ohne Adminrechte. Wenn eine Aktion sie braucht, wird für genau diese Aktion ein eigener Prozess per UAC gestartet.

| Fall | Adminrechte |
| --- | --- |
| Eintrag unter HKLM (für den ganzen Rechner) | ja, eigene UAC-Abfrage |
| Eintrag unter HKCU (nur dieser Benutzer) | **nie**, auch nicht auf Wunsch |
| Store-App | nein, Store-Apps gelten pro Benutzer |
| Nur in winget bekannt (Bereich unbekannt) | keine eigene Erhöhung; winget fordert die UAC bei Bedarf selbst an |

Der Grund für die HKCU-Regel: Den HKCU-Zweig kann jeder Prozess ohne Adminrechte beschreiben. Außerdem läuft die UAC-Abfrage in Firmen oft über ein anderes Adminkonto, und die Aktion würde dann im falschen Benutzerprofil landen.

Zusätzlich wird mit Adminrechten keine Datei gestartet, die der Benutzer verändern könnte. Dazu zählen Dateien im Benutzerprofil, in Temp oder unter `C:\Users\Public` und Dateien mit Schreibrechten für den Benutzer laut ACL der Datei oder ihres Ordners. Das Ergebnis lautet dann `Unsupported` mit Hinweis.

### Erhöhter Helfer

Mit Adminrechten läuft nur ein kleines Helferskript (`src/SoftwareInventory/Elevated/ElevatedHelper.ps1`). Es trifft keine Entscheidungen: Programm, Argumente und Optionen kommen fertig geprüft aus dem Plan. Gestartet wird es mit Windows PowerShell 5.1, das auf jedem Windows 10/11 vorhanden ist. Das Skript ist deshalb 5.1-kompatibel und als UTF-8 mit BOM gespeichert. Aktionen ohne Adminrechte laufen über denselben Helfer, nur ohne UAC.

- `Start-ElevatedHelper` ist die einzige Stelle, die den Prozess startet. Die App (Etappe 3b) ersetzt dort `powershell.exe` durch ihre eigene EXE mit Helfer-Argument, weil sie kein separates PowerShell voraussetzen soll.
- Der Plan steht als Base64-JSON im Argument, nicht in einer Datei.
- Der erhöhte Prozess liest das Helferskript einmal ein, prüft dessen SHA256 gegen den mitgegebenen Wert und führt genau diesen Inhalt aus. Bei einer Abweichung führt er nichts aus.
- Das Ergebnis (Exit-Code, letzte Ausgabezeilen, MSI-Log, Wiederherstellungspunkt) kommt über eine **Named Pipe** zurück, nicht über eine Datei. So schreibt der erhöhte Prozess nie in einen für Benutzer beschreibbaren Ordner.
- Die Pipe hat einen zufälligen Namen und nimmt nur einen Client an. Verbinden dürfen nur Administratoren und SYSTEM, also erhöhte Prozesse.
- Der Aufrufer prüft, ob die Prozess-ID des Clients die des gestarteten Helfers ist und ob die Zufallszahl aus dem Plan zurückkommt. Er wartet nur begrenzt.
- Das MSI-Log entsteht im Temp-Ordner des erhöhten Kontexts und wird nach dem Auslesen gelöscht.

## Ergebnis (`SoftwareInventory.ActionResult`)

| Feld | Bedeutung |
| --- | --- |
| `ActionId` | Kennung; verbindet Ergebnis und Protokoll |
| `Action` | `Update` oder `Uninstall` |
| `Name`, `WingetId`, `WingetSource`, `RegistryKey`, `ProductCode`, `PackageFullName` | Programm |
| `Scope` | `Machine`, `User` oder `Unknown` (aus dem echten Registry-Zweig) |
| `Method` | `Winget`, `Msi`, `Appx`, `QuietUninstallString`, `UninstallString`, `VendorLink` oder `None` |
| `FilePath`, `Arguments`, `CommandLine` | Ausgeführter Befehl; `CommandLine` dient nur der Anzeige |
| `Elevated` | mit Administratorrechten ausgeführt |
| `Result` | siehe unten |
| `ExitCode`, `ExitCodeHex` | Exit-Code; winget-Codes zusätzlich als `0x8A15…` |
| `Message` | Klartext |
| `Output` | Letzte Zeilen der Ausgabe von winget bzw. des Installationsprogramms |
| `InstallerLog` | Pfad des aufgehobenen MSI-Logs (`.zip`, nur bei Fehlern) |
| `VersionBefore`, `VersionAfter`, `PresentBefore`, `PresentAfter` | Zustand vor und nach der Aktion |
| `RestorePoint`, `RestorePointMessage` | `NotRequested`, `Planned` (nur `-WhatIf`), `Created`, `Skipped`, `NotAvailable`, `Failed` |
| `VendorUrl` | Herstellerlink bei `ManualUpdateRequired` |
| `NextMethod` | Nächste mögliche Methode, falls diese fehlschlägt |
| `StartedAt`, `CompletedAt` | UTC |

| `Result` | Bedeutung |
| --- | --- |
| `Planned` | `-WhatIf`: nichts ausgeführt |
| `Succeeded` | Exit-Code passt und Zustand geprüft (Eintrag weg bzw. Version höher) |
| `SucceededRebootRequired` | Exit-Code 3010/1641 bzw. winget „Neustart nötig“; der Eintrag kann bis zum Neustart bleiben |
| `NotVerified` | Exit-Code meldet Erfolg, der Zustand hat sich aber nicht geändert |
| `Cancelled` | Abgebrochen (1602, winget `CANCELLED_BY_USER`) oder nicht bestätigt |
| `ElevationDenied` | UAC-Abfrage abgelehnt |
| `NotInstalled` | Programm nicht (mehr) vorhanden (vorab erkannt, 1605, winget `NO_APPLICATIONS_FOUND`) |
| `NoUpdateAvailable` | winget findet kein passendes Update |
| `ManualUpdateRequired` | Kein winget-Paket; siehe `VendorUrl` |
| `Unsupported` | Nicht ausführbar, z. B. Interpreter, beschreibbarer Ort, keine Methode |
| `Timeout` | Keine Rückmeldung innerhalb von `-TimeoutMinutes` (Standard 60); das Programm wird nicht beendet |
| `Failed` | Fehler; `Message` nennt den Grund (z. B. „Das Programm läuft noch“) |

Die Abbildung der Exit-Codes steht in `src/SoftwareInventory/Private/ExitCode.ps1`. Grundlage für winget ist die offizielle Liste [returnCodes.md](https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md). Unbekannte Codes werden zu `Failed` mit dem Code in Hex.

## Wiederherstellungspunkt

Standardmäßig aus. Einschalten mit `Set-InventorySetting -Enable RestorePoint` oder pro Aufruf mit `-CreateRestorePoint`. `-CreateRestorePoint:$false` schaltet ihn für einen Aufruf ab.

- Angelegt wird er mit `Invoke-CimMethod -Namespace root/default -ClassName SystemRestore -MethodName CreateRestorePoint`, im erhöhten Helfer vor der Aktion. `Checkpoint-Computer` gibt es in PowerShell 7 nicht.
- Bei Aktionen ohne Adminrechte gibt es dafür einen eigenen, kurzen UAC-Aufruf. Die Aktion selbst läuft danach im Benutzerkontext.
- Ein Fehler beim Wiederherstellungspunkt bricht die Aktion nie ab. Er wird angezeigt und protokolliert.

| Status | Wann |
| --- | --- |
| `Created` | Ein neuer Punkt ist da (Vergleich der neuesten `SequenceNumber` vorher und nachher) |
| `Skipped` | Windows hat keinen Punkt angelegt, meist weil in den letzten 24 Stunden schon einer angelegt wurde (Windows überspringt das stillschweigend) |
| `NotAvailable` | Computerschutz ist ausgeschaltet oder der Dienst deaktiviert |
| `Failed` | Anderer Fehler, auch eine abgelehnte UAC-Abfrage nur für den Punkt; der Grund steht in `RestorePointMessage` |

## Protokoll

`%LOCALAPPDATA%\SoftwareInventory\logs\actions\<yyyy-MM-dd>.jsonl` (Datum in UTC), eine JSON-Zeile pro Eintrag. Jede Aktion schreibt einen Eintrag `Started` und einen Eintrag `Completed`. Fehlt der Abschluss, zeigt `Get-ActionLog` die Aktion als `Incomplete`, weil sie noch läuft oder unterbrochen wurde. Nicht ausführbare Aktionen (`NotInstalled`, `Unsupported`, `ManualUpdateRequired`) werden mit einem Eintrag protokolliert, `-WhatIf` gar nicht.

Ein Eintrag enthält:
- `Timestamp`, `Phase`, `User`, `ModuleVersion`, `SchemaVersion`
- alle Felder des Ergebnisses
- von der Ausgabe nur die letzten 20 Zeilen

API-Schlüssel (`NVD_API_KEY`, `GITHUB_TOKEN`) werden vor dem Schreiben entfernt. Geschrieben wird nur vom Prozess ohne Adminrechte, unter einem benannten Mutex. So entsteht keine Datei, die der Benutzer nicht lesen kann. Beschädigte oder abgeschnittene Zeilen überspringt `Get-ActionLog` mit einer Warnung.

```powershell
Get-ActionLog -After (Get-Date).AddDays(-7)
Get-ActionLog -Name 'VLC*' -Action Uninstall
Get-ActionLog -Result Failed, NotVerified -Last 5
```

## Selbstbereinigung

Beim Laden des Moduls werden `logs\` und `cache\` unter `%LOCALAPPDATA%\SoftwareInventory` bereinigt:
- Dateien, die älter als `LogRetentionDays` sind (Standard 30), werden gelöscht.
- Danach wird, solange die Gesamtgröße über `LogMaxSizeMB` liegt (Standard 100), das Älteste zuerst gelöscht.
- Leere Ordner werden entfernt. Gesperrte Dateien werden übersprungen.
- Gespeicherte Scans (`scans\`) sind Nutzdaten und bleiben.

MSI-Logs werden nach Erfolg gar nicht erst gespeichert. Bei Fehlern werden sie komprimiert unter `logs\installer\<ActionId>.zip` aufgehoben. In Temp bleibt nichts liegen.

```powershell
Set-InventorySetting -LogRetentionDays 14 -LogMaxSizeMB 50
```

## Integrationstest in Windows Sandbox

Die Unit-Tests ersetzen winget, msiexec, Registry, Appx, UAC und CIM durch Mocks. Echt ausgeführt wird dabei nur der Helfer unter Windows PowerShell 5.1, ohne Adminrechte und mit harmlosen Programmen wie `where.exe`. Auf dem Entwicklungsrechner wird nichts installiert oder deinstalliert.

Den echten Ablauf prüft ein Skript in Windows Sandbox. Dafür muss die Windows-Funktion „Windows-Sandbox“ aktiviert sein.

```powershell
.\tests\Sandbox\Start-ActionSandbox.ps1
```

Das Repository wird schreibgeschützt eingebunden. In der Sandbox öffnet sich ein Konsolenfenster, in dem automatisch Folgendes abläuft. Eingreifen ist nicht nötig. Es darf nur eine Sandbox gleichzeitig laufen, eine alte also vorher schließen.

1. PowerShell 7.6.8 und winget 1.29.380 werden aus den offiziellen GitHub-Releases geladen. Das Skript prüft den fest hinterlegten SHA256 und bei der MSI zusätzlich die Microsoft-Signatur. MSIX-Pakete prüft `Add-AppxPackage` selbst. Danach wird beides installiert.
2. Das Skript installiert Testprogramme und spielt die Aktionen durch:
   - 7-Zip 24.08 als MSI: zuerst Update über winget mit Adminrechten, danach Deinstallation über MSI mit Wiederherstellungspunkt (in der Sandbox meist `NotAvailable`) und erneut, wobei `NotInstalled` erwartet wird
   - WinMerge: Deinstallation über `QuietUninstallString`
   - Oh My Posh im Benutzerbereich: Deinstallation über winget ohne Adminrechte
   - eine Store-App, falls vorhanden
3. Die Ergebnisse stehen in der Konsole und in `tests\Sandbox\out\ergebnis-<Zeit>.json`, die Konsolenausgabe in `konsole-<Phase>-<Zeit>.txt`. Steht „Fertig“ in der Konsole, kann die Sandbox geschlossen werden.

Die Sandbox-Anmeldung ist bereits Administrator. Den Fall „UAC über ein anderes Adminkonto“ deckt sie deshalb nicht ab. Dafür einmal manuell auf einer VM mit einem Standardbenutzer prüfen:

1. Als Standardbenutzer ein Programm für alle Benutzer (HKLM) per `Uninstall-Software` entfernen und die UAC-Abfrage mit dem Adminkonto bestätigen. Erwartet wird `Succeeded`, `Elevated = True` und ein lesbarer Protokolleintrag im Profil des Standardbenutzers.
2. Ein Programm im Benutzerbereich (HKCU) entfernen. Erwartet werden keine UAC-Abfrage und `Elevated = False`.
3. Die UAC-Abfrage ablehnen. Erwartet wird `ElevationDenied`.
