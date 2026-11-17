---
name: etappe-test
description: Baut die betroffenen Projekte und startet einen Teillauf von tests/Invoke-IsolatedTests.ps1 mit Logdatei und Frist. Nutze es während der Arbeit an einem Teilschritt, mit dem Testbereich als Argument (z. B. tests/Unit/Rating.Tests.ps1 oder ein xUnit-Filter).
---

# Teillauf der Tests (CLAUDE.md, Arbeitsteilung)

Argument: `$ARGUMENTS` (Pester-Pfade unter `tests/Unit/` und/oder ein xUnit-Filter; leer = nachfragen, nie raten).

1. **Erst bauen.** Betroffene Projekte mit `dotnet build` bauen (Modul-DLL `src/SoftwareInventory.Native`, App, Testprojekt, je nachdem, was geändert ist). Nur bei Build ohne Fehler weitermachen; sonst den Build reparieren und nichts testen.
2. **Teillauf starten**, nie `Invoke-Pester` oder `dotnet test` direkt (der Hook `block-direct-tests` blockiert das):
   - Git Bash: `pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -PesterPath <Pfade> [-XunitFilter <Filter>] > <Logdatei im Scratchpad> 2>&1`
   - Nur Pester: `-PesterOnly`; nur xUnit: `-XunitOnly`.
   - Der volle Lauf (mit `-IncludeIntegration`) gehört nicht hierher, sondern in `/pr-bereit`.
3. **Warten mit Frist**, höchstens 10 Minuten (`timeout 590`): nur auf die Abschlusszeile `ISOLATED-TESTS-EXIT <Code>` im Log. Nie auf `dotnet`-Prozesse warten, nie ohne Timeout. Fehlt die Zeile nach der Frist: „Lauf nicht beendet“ melden.
4. **Ergebnis kurz berichten:** Exit-Code (0 bestanden, 1 Fehlschlag, 2 Parameterfehler, 3 unerwarteter Fehler, 4 nichts oder nicht alles ausgeführt), Zahlen für Pester und xUnit und bei Fehlschlägen die Namen mit der Meldung. Bei CS2001, BG1002 oder MSB3061 (VS Code baut parallel) den Lauf einmal wiederholen und das erwähnen.
5. Skripte aus `tests/Sandbox` nie starten. Keine echten Aktionen (Updates, Deinstallationen) auslösen.
