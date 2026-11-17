---
name: pr-bereit
description: Bereitet den Pull Request des aktuellen Branches vor: Vollauf (oder bei reinen Doku-/Regel-PRs der Teillauf), reviewer einmal, PR-Text mit Attribution, Push und PR öffnen. Nutze es, wenn ein Teilschritt fertig und committet ist.
---

# PR vorbereiten (CLAUDE.md, Git-Arbeitsweise und Arbeitsteilung)

Voraussetzung: Arbeitskopie sauber und committet, Branch ist nicht `main`. Sonst abbrechen und melden.

1. **Art des PR bestimmen** mit `git diff --name-only main...HEAD`:
   - **Rein Doku/Regeln** (nur `.md`, `.claude/`, Agentendefinitionen o. Ä., kein Code): nur Teillauf `-PesterPath tests/Unit/SourceFiles.Tests.ps1` (bei Hook-Änderungen zusätzlich `tests/Unit/Hooks.Tests.ps1`). Kein `reviewer`, kein Vollauf.
   - **Sonst Code:** weiter mit 2.
2. **Bauen**, dann **Vollauf** mit `pwsh -NoProfile -File tests/Invoke-IsolatedTests.ps1 -IncludeIntegration > <Log> 2>&1`, Frist 30 Minuten, nur auf `ISOLATED-TESTS-EXIT <Code>` warten. Nur Exit 0 gilt als bestanden; sonst melden und nicht weitermachen.3. **`reviewer` genau einmal** starten (Subagent, sieht nur committete Stände). Nur wenn kritische Funde behoben wurden, läuft er danach erneut. Bericht kurz zusammenfassen; nicht behobene mittlere und geringe Funde mit Begründung in die PR-Beschreibung.
4. **PR-Text** als Datei im Scratchpad schreiben (Write): Was, Tests (Zahlen aus dem Lauf), Review-Funde, Offenes. Am Ende die Zeile `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
5. **Pushen und PR öffnen:** `git push -u origin <Branch>`, dann `"C:\Program Files\GitHub CLI\gh.exe" pr create --repo normbox/Softwareverwaltung --base main --head <Branch> --title <englischer Titel> --body-file <Datei>`.
6. **Nie mergen.** Den Merge-Befehl nennt Claude nur: `! "C:\Program Files\GitHub CLI\gh.exe" pr merge <Nr> --repo normbox/Softwareverwaltung --merge`. Der Hook `block-git-risks` blockiert `gh pr merge` ohnehin.
