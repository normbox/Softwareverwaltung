# Entwicklung

## Einrichtung

```powershell
winget install --id Microsoft.PowerShell --exact          # PowerShell 7.6 LTS
pwsh -c "Install-PSResource Pester,PSScriptAnalyzer,Microsoft.WinGet.Client -Scope CurrentUser -TrustRepository"
winget install Microsoft.DotNet.SDK.10                    # ab Etappe 3
```

Das Modul zielt auf PowerShell 7 (die Engine, die die App über `Microsoft.PowerShell.SDK` einbettet). Windows PowerShell 5.1 wird nicht unterstützt. Einzige Ausnahme ist der erhöhte Helfer `src/SoftwareInventory/Elevated/ElevatedHelper.ps1` (siehe [AKTIONEN.md](AKTIONEN.md)). Er läuft unter 5.1 und unter 7, nutzt nur Sprachmittel von 5.1 und ist als UTF-8 **mit BOM** gespeichert, damit 5.1 Umlaute richtig liest. Dasselbe gilt für `tests/Sandbox/*.ps1`.

## Tests

```powershell
pwsh -c "Invoke-Pester ./tests/Unit"                     # Unit-Tests
pwsh -c "Invoke-Pester ./tests/Integration"              # gegen das echte System
pwsh -c "Invoke-ScriptAnalyzer ./src/SoftwareInventory -Recurse -Settings ./PSScriptAnalyzerSettings.psd1"
.\tests\Sandbox\Start-ActionSandbox.ps1                  # Aktualisieren/Deinstallieren echt testen, nur in Windows Sandbox
```

Die Unit-Tests führen nie echte Installationen, Updates oder Deinstallationen aus; winget, msiexec, Registry, Appx, UAC und CIM werden ersetzt. Echt gestartet wird nur der Helfer unter `powershell.exe` 5.1, ohne Adminrechte und mit harmlosen Programmen (`where.exe`, `timeout.exe`).

## Texte und Meldungen

Neue Texte stehen nie fest im Code (siehe `CLAUDE.md`).

- **App:** Texte stehen in `src/Softwareverwaltung.App/Resources/Strings.resx`. In XAML heißt das `{loc:Text Schlüssel}`, in C# `AppText.Get("Schlüssel")` bzw. `AppText.Format("Schlüssel", …)`. Codes aus dem Modul übersetzt die App über Präfix und Code, z. B. `ActionResultFailed`.
- **Modul:** Texte stehen in `src/SoftwareInventory/SoftwareInventory.Strings.psd1`, abgerufen mit `Get-LocalizedString`. Weitere Sprachen kommen später als Unterordner (`en-US\SoftwareInventory.Strings.psd1`) mit denselben Schlüsseln.
- **Meldungen des Moduls:** Gründe, Status, Hinweise und Fehler sind Objekte vom Typ `SoftwareInventory.Message` mit drei Feldern:
  - `Code`, z. B. `ServiceDisabled`;
  - `Args`, z. B. `@('NVD')`; Args dürfen selbst Meldungen sein;
  - `Text`, in der Sprache der Oberfläche; der Schlüssel in der psd1 ist `Reason<Code>`.

  Logik und Tests prüfen nur `Code` und `Args`, angezeigt wird `Text`. Erzeugt werden Meldungen mit `New-InventoryMessage`.
- **Gespeicherte Meldungen:** Das Aktionsprotokoll speichert Code und Args. `Get-ActionLog` baut den Text neu auf. Ältere Einträge mit reinem Text erscheinen als `LegacyText` mit dem Zusatz „(älterer Eintrag)“.
- **Erhöhter Helfer:** Er liefert nur Codes und Args, den Text bildet das Modul.
- **Sprache:** Die eingebettete Engine läuft in der UI-Sprache der App. Ohne Übersetzung gelten die deutschen Basistexte.
- **Tests:** Sie prüfen, dass jeder benutzte Schlüssel und Code einen Text hat und dass in XAML keine festen Texte stehen.

## Machbarkeitsprüfung (24.10.2026)

Getestet mit PowerShell 7.6.8, einmal in `pwsh` und einmal eingebettet in eine .NET-10-Konsolen-App mit `Microsoft.PowerShell.SDK` 7.6.8:

| Quelle | pwsh | eingebettet |
| --- | --- | --- |
| Registry (Uninstall-Schlüssel) | ok | ok |
| `Get-AppxPackage` (ohne `-UseWindowsPowerShell`) | ok | ok |
| `Get-WinGetPackage` (Microsoft.WinGet.Client 1.29) | ok | ok |

Folgerungen:

- Kein Ersatzweg über die Textausgabe von `winget list`. Fehlt das Modul, meldet das Inventar „winget nicht verfügbar“ und liefert die übrigen Quellen.
- winget-Pakete lassen sich über `GetPackageVersionInfo(...).ProductCodes` den Registry-Einträgen zuordnen (enthält Schlüsselnamen und MSI-GUIDs). Einträge ohne Katalogtreffer tragen IDs wie `ARP\Machine\X64\<Schlüssel>` bzw. `MSIX\<PackageFullName>`.
- Für Etappe 3 merken: Die App muss `Microsoft.WinGet.Client` mitliefern, da es beim Nutzer nicht installiert sein muss.

## Machbarkeitsprüfung Etappe 2 (24.10.2026)

Abgefragt ohne API-Schlüssel und ohne Token; gesendet wurden nur Produktnamen, CPEs und CVE-IDs.

| Prüfung | Ergebnis |
| --- | --- |
| NVD `cves/2.0?cpeName=…:7-zip:7-zip:24.08:…` | 14 CVEs, darunter CVE-2025-0411, obwohl die NVD dort nur `versionEndExcluding 24.09` einträgt. NVD wertet Versionsbereiche selbst aus. |
| dieselbe Abfrage mit Version `24.08.5` (nicht im CPE-Wörterbuch) | ebenfalls 14 CVEs; die Version muss nicht im Wörterbuch stehen |
| NVD `cpes/2.0?keywordSearch=` | brauchbar als Vorschlag: VLC eindeutig (`videolan:vlc_media_player`), Notepad++ mit drei Hersteller-Schreibweisen, „Python“ über 22.000 Treffer. Ergebnis daher nur als unbestätigter Vorschlag. |
| CISA KEV (JSON-Feed) | 1.756 Einträge, ca. 1 s; Felder u. a. `cveID`, `dateAdded`, `knownRansomwareCampaignUse` |
| EPSS (`api.first.org/data/v1/epss?cve=a,b,c`) | Sammelabfrage funktioniert; `epss` und `percentile` als Zahl in Textform |
| GitHub `releases/latest` ohne Token | 60 Anfragen pro Stunde; Tags mit Präfix (`v8.9.8.1`) |

Folgerungen:

- Für die CVE-Suche reicht `cpeName` mit der installierten Version; das Modul muss Versionsbereiche nicht selbst auswerten.
- Ohne NVD-Schlüssel höchstens 5 Anfragen pro 30 s, mit Schlüssel 50. Der Schlüssel ist optional und darf nie in Protokollen, Snapshots oder Berichten erscheinen.
- Zeitangaben aus Feeds mit `ConvertFrom-Json -DateKind String` lesen (sonst wandelt PowerShell sie in Ortszeit um).
- Versionsnormalisierung muss Präfixe wie `v` und Zusätze nach der Versionsnummer entfernen.

### Nachprüfung für Etappe 2b (Versionsformate und Konfigurationen)

| Prüfung | Ergebnis |
| --- | --- |
| `cpeName` mit `24.08`, `24.8` und `24.8.0.0` (7-Zip) | jeweils dieselben 14 CVEs – NVD normalisiert Versionen selbst; die Registry-Schreibweise kann direkt verwendet werden |
| `cpeName` mit `3.13.15` und `3.13.15150.0` (Python) | jeweils dieselben 5 CVEs |
| Python-Treffer CVE-2009-2940, CVE-2009-3720 | Python steht dort nur als Umgebung (`vulnerable=false`); verwundbar sind PyGreSQL bzw. libexpat |
| VLC 3.0.20 | 0 CVEs, obwohl CVE-2024-46461 erst in 3.0.21 behoben ist: Die CVE hat den Status „Deferred“ und **keine** CPE-Konfiguration |

Folgerungen:

- Treffer von `cpeName` lokal filtern: Nur CVEs zählen, bei denen das eigene Produkt mit `vulnerable=true` eingetragen ist und die Version im angegebenen Bereich liegt.
- Sonderzeichen in Versionen nach CPE 2.3 mit `\` maskieren (z. B. `0.4.26\+4`).
- Die NVD analysiert seit 2024 viele neue CVEs verzögert oder gar nicht. Solche CVEs findet `cpeName` nie. Ausgleich: KEV-Einträge werden zusätzlich über Hersteller/Produkt aus dem Katalog zugeordnet; ohne Versionsdaten gelten sie als „möglicherweise betroffen – Version nicht prüfbar“ (Ampel: Gelb mit Hinweis).
