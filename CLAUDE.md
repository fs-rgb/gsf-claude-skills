# Arbeiten in diesem Repo

Dieses Repo ist die Sammelstelle für die Claude-Skills von GSF. Es wird nicht gebaut und nicht
getestet — es wird verteilt. Was hier liegt, landet über Raw-URLs direkt in fremden Projekten.

## Regel 1 — die README wird mitgeändert

**Jede Änderung an der Repo-Struktur zieht ein Update der [README.md](README.md) nach sich**, im
selben Commit. Die README ist die einzige Stelle, an der steht, was es hier gibt; läuft sie aus dem
Takt, findet niemand mehr etwas.

Nachzuziehen ist:

- Neuer Skill oder neues Bündel → Zeile in *Was hier liegt*
- Ordner umbenannt, verschoben oder entfernt → *Was hier liegt* plus die Links
- Aufbau-Konvention geändert → Abschnitt *Aufbau*

Die README eines Bündels beschreibt dessen Inhalt, die Root-README nur, welche Bündel es gibt.
Bündel-Details gehören nicht in die Root-README.

## Regel 2 — Raw-URLs nach jedem Verschieben prüfen

Die Skills laden ihre Assets beim Setup selbst nach, mit fest verdrahtetem Pfad:
`https://raw.githubusercontent.com/fs-rgb/gsf-claude-skills/main/<pfad-im-repo>`.

Ein verschobener Ordner bricht das **still** — GitHub liefert eine Fehlerseite, die ungeprüft als
Skript oder Config im Zielprojekt landet. Nach jedem Verschieben deshalb:

```bash
grep -rn "raw.githubusercontent" --include="*.md" --include="*.json" .
```

und die Treffer mitziehen.

## Regel 3 — Skill-Ordner nie verschachteln

Ein Skill-Ordner (der mit der `SKILL.md`) ist die Installationseinheit: genau dieser Ordner wird
nach `~/.claude/skills/<name>/` kopiert. Liegt ein Skill-Ordner in einem anderen, lässt sich der
innere nicht mehr einzeln installieren. Mehrere zusammengehörende Skills kommen deshalb
nebeneinander in einen Bündel-Ordner, der selbst **keine** `SKILL.md` hat.

## Sprache

Skills, READMEs und Commit-Messages auf Deutsch. Commit-Messages ohne Umlaute — die Historie soll
in jedem Terminal lesbar bleiben.
