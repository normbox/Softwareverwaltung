# Ampel und Sicherheitsbericht

```powershell
Set-InventorySetting -Enable GitHub, WingetSearch, NVD, KEV, EPSS     # externe Dienste einzeln aktivieren
$ratings = @(Get-SoftwareInventory) + @(Get-PortableSoftware) | Get-SecurityRating
$ratings | Where-Object Rating -in 'Red', 'Yellow' | Format-Table Name, Version, Rating, Reasons
$ratings | Export-SecurityReport -Path "$env:USERPROFILE\Desktop\Sicherheitsbericht.html"
```

`Get-SecurityRating` ruft [Test-SoftwareUpdate](VERSIONSABGLEICH.md) und [Get-SoftwareVulnerability](SCHWACHSTELLEN.md) mit den aktivierten Diensten auf und bewertet jedes Programm. `Export-SecurityReport` nimmt diese Ergebnisse oder direkt Datensätze entgegen.

## Ampel

| Stufe | Wann |
| --- | --- |
| **Rot** | Sicher betroffen (`Affected`) von einer aktiv ausgenutzten Lücke (CISA KEV) oder einer kritischen Lücke (CVSS ab 9,0) |
| **Gelb** | Andere sicher betroffene Lücken; „möglicherweise betroffen“ (z. B. KEV-Eintrag ohne NVD-Versionsdaten, junger NVD-Eintrag ohne Versionsgrenze); Update verfügbar (auch unbestätigt, dann gekennzeichnet) |
| **Grün** | Sicherheitsprüfung gelaufen (NVD abgefragt) und nichts gefunden |
| **Grau** | Nicht auf Lücken geprüft – immer mit Grund, z. B. „Keine CPE zugeordnet“, „Dienst NVD nicht aktiviert“, „Version nicht lesbar“ |

- Grün setzt eine gelaufene Sicherheitsprüfung voraus. „Aktuell laut winget“ allein ergibt Grau mit dem Hinweis „Version aktuell“ – ein nicht geprüftes Programm erscheint nie als Grün.
- Hinweise (`Informational`, z. B. NVD-Altdaten ohne Versionsangabe älter als 5 Jahre) färben nie.
- `Reasons` nennt immer die Gründe der Stufe, bei Rot zusätzlich die gelben Gründe. Jeder Grund ist eine Meldung mit `Code`, `Args` und `Text`, z. B. `KevAffected` oder `NotCheckedBecause` mit dem eigentlichen Grund als Arg.
- Der Bericht übernimmt Texte, Datumsformat und Sprachangabe aus der Sprache der Oberfläche.

## Bericht

- Eine HTML-Datei ohne externe Ressourcen (offline lesbar, weitergebbar), heller und dunkler Modus.
- Sortiert nach Dringlichkeit: Rot, Gelb, Grau, Grün.
- Filter: Alle, Updates verfügbar, Sicherheitsrisiko (Lücken außer Hinweisen), je Ampelstufe.
- Je Programm aufklappbar: Quelle und Ort, CPE (mit Hinweis, wenn vom Benutzer bestätigt), CVEs mit Link zur NVD, Bewertung, CVSS, EPSS, KEV-Kennzeichnung, Hinweisen und Kurzbeschreibung.
- Datenschutz: Das Benutzerprofil erscheint als `%USERPROFILE%`, der Rechnername als `%COMPUTERNAME%`; API-Schlüssel kommen nicht vor. Programmnamen und Versionen sind enthalten.
- Alle Werte werden HTML-maskiert.
