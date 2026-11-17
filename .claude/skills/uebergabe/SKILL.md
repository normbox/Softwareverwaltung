---
name: uebergabe
description: Aktualisiert UEBERGABE.md und die Merk-Notiz des Projekts am Sitzungsende. Reine Doku-Arbeit, dafür genügt Sonnet. Nutze es, wenn die Sitzung endet oder ein Etappenschritt gemergt ist.
---

# Übergabe aktualisieren

Reine Dokumentation, kein Code: Sonnet genügt. Berührt die nächste Aufgabe Sicherheitslogik (Helfer, Registry, Rechte, Prüfregeln), darauf hinweisen und `/model opus` vorschlagen.

1. **Stand erheben:** `git status -sb`, `git log --oneline -8`, `git branch` und `"C:\Program Files\GitHub CLI\gh.exe" pr list --repo normbox/Softwareverwaltung --state all --limit 5`. Nur Tatsachen übernehmen, nichts erfinden (z. B. keine Testzahlen ohne Lauf).
2. **`UEBERGABE.md`** (nur den Block „Stand <Datum>“ ganz oben und „Als Nächstes“ anpassen; ältere Absätze stehen lassen): gemergte PRs mit `main`-Hash, offene PRs und Branches, letzter Vollauf (Exit, Zahlen) nur wenn bekannt, offene Beobachtungen, Reihenfolge der nächsten Schritte. Datum im Format `TT.MM.JJJJ`. Mit Edit ändern, nie über die Shell (Hook `block-source-via-shell`).
3. **Merk-Notiz** unter `C:\Users\normb\.claude\projects\E--KI-Projekte-Softwareverwaltung\memory\`: vorhandene Datei zum Projektstand ergänzen oder berichtigen (nicht doppeln), in `MEMORY.md` bleibt es bei einer Zeile pro Eintrag. Falsch gewordene Einträge löschen.
4. Änderungen an `UEBERGABE.md` brauchen einen Branch (nie auf `main` committen); als reiner Doku-PR gilt nur der Teillauf `-PesterPath tests/Unit/SourceFiles.Tests.ps1`.
5. Am Ende kurz berichten, was geändert wurde und was die neue Sitzung als Erstes tun soll.
