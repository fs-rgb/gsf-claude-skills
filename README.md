# gsf-claude-skills

Sammelstelle für die Claude-Skills von GSF — vor allem für die, die aus mehr als einer Datei
bestehen.

Ein Skill, der nur aus einer `SKILL.md` besteht, lässt sich noch per Copy-Paste weiterreichen.
Sobald aber Hook-Skripte, Konfigurationsvorlagen oder Anleitungen dazugehören, geht das nicht mehr:
dann braucht es einen Ort, von dem Claude sich die Dateien zur Laufzeit nachladen kann und an dem
eindeutig ist, welche Version die aktuelle ist. Das ist dieses Repo.

**Wenn du einen Skill nur benutzen willst, brauchst du das Repo nicht.** Skills schaltest du in
deinem Profil frei: *claude.ai → Einstellungen → Skills*. Hier geht es um Weiterentwickeln und
Verteilen.

## Was hier liegt

| Ordner | Worum es geht |
|---|---|
| [`projektwissen/`](projektwissen/) | Zwei ineinandergreifende Skills — `decision-records` und `doku-update-sync` — die dafür sorgen, dass Projektwissen in Dateien im Projekt landet statt in einzelnen Chatverläufen. Mit 2-Seiten-Anleitung zum Verteilen. Details in [`projektwissen/README.md`](projektwissen/README.md). |

## Aufbau

Ein Ordner pro Bündel, darin ein Ordner pro Skill:

```
<buendel>/
    README.md              worum es geht, wie man es benutzt, wie man es weiterentwickelt
    <skill-name>/
        SKILL.md           der Skill selbst
        assets/            Dateien, die der Skill zur Laufzeit in ein Projekt legt
    <weiterer-skill>/
        SKILL.md
```

Zwei Regeln halten das benutzbar:

- **Ein Skill-Ordner ist die Installationseinheit.** Genau dieser Ordner landet später unter
  `~/.claude/skills/<name>/` oder `<repo>/.claude/skills/<name>/`. Deshalb liegt **nie ein
  Skill-Ordner in einem anderen** — der innere ließe sich sonst nicht mehr einzeln installieren.
- **Ein Skill ohne Zubehör braucht kein Bündel.** Er darf direkt im Root liegen, als
  `<skill-name>/SKILL.md`.

Im Root liegt außerdem `.gitattributes` — es normalisiert Zeilenenden auf LF und markiert PDFs und
PNGs als binär. Es gehört ins Root, damit es fürs ganze Repo gilt.

## Skills verteilen

Installiert wird ein Skill nicht aus diesem Repo, sondern **in Claude hochgeladen** — entweder
persönlich unter *claude.ai → Einstellungen → Skills* oder von einer Administratorin für die ganze
Organisation. Danach steht er auch in Claude Code zur Verfügung, sobald man dort mit demselben
Konto angemeldet ist.

Hochgeladen wird **je Skill genau der Ordner, in dem die `SKILL.md` direkt liegt**:

- `projektwissen/decision-records/` — ein Upload
- `projektwissen/doku-update-sync/` — ein zweiter Upload
- `projektwissen/` selbst **nicht**: das ist nur die Klammer, kein Skill. Ein Ordner ohne eigene
  `SKILL.md` an der Wurzel wird nicht als Skill erkannt.

Zwei Hinweise dazu:

- **`assets/` am besten mitschicken.** Dann braucht das Setup im Zielprojekt keinen Netzzugriff.
  Ohne `assets/` lädt Claude die Dateien von den Raw-URLs nach — das Repo ist öffentlich, das
  funktioniert also auch für Kolleginnen ohne Zugriff darauf, nur eben nicht offline.
- **Die Skills wirken in Claude Code, nicht im Web-Chat.** Sie legen Dateien im Repo an und
  registrieren Hooks in `.claude/settings.json`. Eine Freigabe in der Organisation macht sie
  verfügbar; gearbeitet wird mit ihnen im Projekt.

Die [Anleitung](projektwissen/Anleitung-Projektwissen.pdf) ist nicht Teil eines Uploads — die geht
an Menschen, nicht an Claude.

## Etwas ändern oder hinzufügen

**Wer etwas an diesem Repo ändert, aktualisiert die README mit.** Das ist keine Höflichkeitsregel:
die README ist die einzige Stelle, an der steht, was es hier überhaupt gibt. Konkret heißt das:

| Änderung | Was in der README nachzuziehen ist |
|---|---|
| Neuer Skill oder neues Bündel | Eine Zeile in *Was hier liegt* |
| Ordner umbenannt oder verschoben | *Was hier liegt* und die Links — **und die Raw-URLs, siehe unten** |
| Aufbau-Konvention geändert | Der Abschnitt *Aufbau* |
| Skill entfernt | Zeile raus, und prüfen, ob ein anderer Skill auf ihn verweist |

Die README eines Bündels beschreibt dessen Inhalt; diese hier beschreibt nur, welche Bündel es gibt.
Was nur ein Bündel betrifft, gehört also nicht hierher.

### Vorsicht beim Verschieben: die Skills laden sich selbst nach

Die Skills in diesem Repo holen sich ihre Assets beim Setup per Raw-URL von hier, mit dem Pfad fest
verdrahtet:

```
https://raw.githubusercontent.com/fs-rgb/gsf-claude-skills/main/<pfad-im-repo>
```

Ein umbenannter oder verschobener Ordner bricht das — und zwar **still**: GitHub liefert dann eine
Fehlerseite, die ungeprüft als Skript oder Config im Zielprojekt landet. Nach jedem Verschieben
deshalb:

```bash
grep -rn "raw.githubusercontent" --include="*.md" --include="*.json" .
```

und die gefundenen Pfade mitziehen.
