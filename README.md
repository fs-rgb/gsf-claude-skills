# gsf-claude-skills

Zwei Claude-Code-Skills, die dafür sorgen, dass Projektwissen nicht verloren geht: Entscheidungen
und Ist-Stand landen automatisch in Dateien im Projekt, statt in einzelnen Chatverläufen zu
versickern. Jeder neue Chat — und jede neue Kollegin — liest sie von dort.

**Wenn du die Skills nur benutzen willst, brauchst du dieses Repo nicht.**
Lies die [Anleitung als PDF](Anleitung-Projektwissen.pdf) (2 Seiten) und schalte die Skills in
deinem Profil frei: *claude.ai → Einstellungen → Skills*.

---

## Die zwei Skills

| Skill | Frage | Verhalten |
|---|---|---|
| [`decision-records`](decision-records/SKILL.md) | „Warum haben wir das so entschieden?" | Fragt dich — die Antwort steht nirgends im Code |
| [`doku-update-sync`](doku-update-sync/SKILL.md) | „Stimmt die Doku noch mit dem Projekt überein?" | Fragt nicht, schreibt still mit — er sieht es selbst |

Sie greifen ineinander:

```
/decision-records            beim ersten Mal in einem Projekt
      |
      +--> richtet doku-update-sync ein: Hooks, Regeln, Doku-Dateien, CLAUDE.md
                 |
                 |  Hook feuert: nach Commit, bei erledigter Aufgabe,
                 |  am Session-Ende, vor git push
                 v
           doku-update-sync   schreibt still, was er selbst sehen kann
                 |
                 +--> fehlt das "Warum"?  -->  decision-records fragt nach
```

Ein Befehl genügt: `/decision-records`. Alles Weitere richtet sich selbst ein.

## Was hier liegt

```
decision-records/SKILL.md          Entscheidungen festhalten (Ask-until-clear)
doku-update-sync/SKILL.md          Doku aktuell halten + Automatik betreiben
doku-update-sync/assets/           Dateien, die das Setup ins Projekt legt:
    doc-sync-gate.ps1                Hook-Skript (Windows)
    doc-sync-gate.sh                 Hook-Skript (macOS/Linux, benötigt jq)
    doc-sync.config.json             Vorlage: was gilt als doku-relevant
    settings-hooks.json              Vorlage: Hook-Registrierung für Claude Code
Anleitung-Projektwissen.pdf        2-Seiten-Anleitung zum Verteilen (+ .html als Quelle)
```

Die Skills werden üblicherweise **ohne** den `assets/`-Ordner verteilt — Claude lädt sich die
Dateien beim Setup von hier nach. Klappt das nicht (kein Netz, Proxy), erzeugt er sie nach der
Spezifikation in *Anhang A* von `doku-update-sync/SKILL.md` selbst. Das Setup scheitert also nicht
an fehlendem Zugriff auf dieses Repo.

## Was das Setup in einem Projekt anlegt

Alles davon wird **mitcommittet**, damit es beim Clone automatisch dabei ist:

```
ARCHITECTURE.md                    Ist-Stand und Architektur-Entscheidungen
docs/decisions/RULES.md            geltende Regeln (IMMER/NIEMALS)
docs/decisions/QUALITY_DECISIONS.md  Produkt- und Prozess-Entscheidungen
docs/decisions/.doc-sync.json      was als doku-relevant gilt, welche Ereignisse prüfen
docs/decisions/.last-sync          bis zu welchem Commit die Doku geprüft ist
.claude/hooks/doc-sync-gate.*      die Automatik
.claude/settings.json              registriert die Automatik
CLAUDE.md                          Verweisblock — sorgt dafür, dass jeder neue Chat die Doku liest
```

Welche dieser Dateien tatsächlich angelegt werden, entscheidet ein kurzes Interview beim ersten
Lauf. Nichts davon passiert ohne ausdrückliche Zustimmung.

## Mitentwickeln

Änderungen an den Hook-Skripten bitte gegen die Fälle in *Anhang A* von
`doku-update-sync/SKILL.md` prüfen — insbesondere die beiden, die still fehlschlagen:

- Das Skript muss bei sauberem Projektzustand **ohne jede Ausgabe** mit Exit 0 enden.
- In PowerShell darf `$ErrorActionPreference` **nicht** auf `Stop` stehen: `git` schreibt Warnungen
  nach stderr, woraus Windows PowerShell sonst einen Abbruch macht — der Hook feuert dann nie, ohne
  dass es auffällt.

Die PDF wird aus `Anleitung-Projektwissen.html` erzeugt:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless=new --disable-gpu `
  --no-pdf-header-footer --print-to-pdf="Anleitung-Projektwissen.pdf" `
  "file:///$PWD/Anleitung-Projektwissen.html"
```
