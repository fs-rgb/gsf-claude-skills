---
name: doku-update-sync
description: >
  Hält die Projektdokumentation eines Repos automatisch aktuell und synchron zum Code — richtet
  beim ersten Lauf (Setup-Modus) die Doku-Struktur, eine Relevanz-Konfiguration, Regeln und
  Claude-Code-Hooks ein und committet sie ins Repo, sodass auch Kolleginnen und Kollegen sie beim
  Clone bekommen. Leitet den Doku-Umfang dabei leise aus dem Repo-Kontext ab und fragt nur bei
  schwer rückgängig zu machenden Punkten nach (Push-Gate-Härtegrad, Hook-Aktivierung). Bei allen
  weiteren Läufen
  (Sync-Modus, meist von einem Hook nach Commit/Aufgabenende/Session-Ende ausgelöst) prüft er
  still, ob es doku-relevantes Delta gibt, schreibt faktisch Ableitbares ohne Rückfrage fort und
  fragt nur bei echter Unklarheit nach. Nutze diesen Skill, wenn ein Repo noch keinen
  Doku-Sync-Mechanismus hat, wenn ein Hook-Reminder auf ihn verweist, wenn Doku und Code
  auseinandergelaufen sind, oder wenn der decision-records-Skill die Automatisierung einrichten
  will. Schwesterskill von decision-records: der erfasst einzelne Entscheidungen, dieser hält den
  Rest der Doku aktuell und betreibt die Automatisierung für beide.
---

# Skill: Doku-Update-Sync

Dokumentation verrottet nicht, weil Leute sie nicht schreiben wollen, sondern weil der Moment, in
dem das Wissen frisch ist, ungenutzt verstreicht. Dieser Skill hängt sich genau an diese Momente —
und arbeitet dort **still**, statt zu erinnern.

**Leitprinzip: still arbeiten, nur bei echter Unklarheit fragen.**
Was aus dem Diff faktisch ableitbar ist (neues Modul, neue Dependency, geändertes Schema,
überholter Ist-Stand), wird ohne Rückfrage geschrieben. Gefragt wird nur, wenn eine **Entscheidung**
erkennbar ist, deren Begründung nicht im Code steht — dafür gibt es `decision-records`.

## Verhältnis zu `decision-records`

| | `decision-records` | `doku-update-sync` (dieser Skill) |
|---|---|---|
| Frage | „Warum haben wir uns so entschieden?" | „Beschreibt die Doku noch, was tatsächlich da ist?" |
| Auslöser | Eine Entscheidung ist gefallen | Ein Hook feuert, oder Doku ist gedriftet |
| Interaktion | Immer Ask-until-clear | Standardmäßig stumm, fragt nur im Ausnahmefall |
| Zuständig für Hooks | nein — delegiert hierher | **ja** — betreibt die Automatisierung für beide |

`decision-records` Schritt 5 ruft diesen Skill auf. Erkennt dieser Skill im Delta eine
**begründungsbedürftige Entscheidung**, übergibt er umgekehrt an `decision-records`. Keine
gegenseitige Rekursion: pro Lauf höchstens eine Übergabe je Richtung.

---

## Modus bestimmen (erster Schritt, immer)

Existiert im Repo-Root `docs/decisions/.doc-sync.json`?

- **Nein → Setup-Modus** (Schritte S1–S6). Standardmäßig leise — aus S1 ableiten und annehmen;
  Rückfragen nur zu Punkten, die schwer rückgängig zu machen sind (siehe S2, S4b, S5).
- **Ja → Sync-Modus** (Schritte Y1–Y7). Still, hier wird bewusst fast nie gefragt.

Wurde der Skill von einem Hook ausgelöst (Reminder-Text im Kontext) und die Config fehlt trotzdem,
ist das ein Defekt — melden statt stillschweigend neu aufzusetzen.

---

# Setup-Modus

Läuft einmal pro Repo. Ziel: nicht „ein Standard-Doku-Gerüst hinstellen", sondern **herausfinden,
welche Doku dieses konkrete Projekt tatsächlich braucht** — und nur die automatisieren.

## S1 — Bestand aufnehmen (vor dem ersten Wort ans Repo)

Lesen, nicht raten:

- Vorhandene Doku: `README.md`, `ARCHITECTURE.md`, `docs/**`, `CLAUDE.md`, `CONTRIBUTING.md`, `*.md` im Root.
- Projekttyp: Manifeste (`package.json`, `pyproject.toml`, `go.mod`, …), Ordnerstruktur, vorhandene
  Workflow-/Config-Dateien. Ein Repo aus n8n-Workflow-Exports braucht andere Doku als ein Backend-Service.
- Git-Historie: `git log --oneline -30`, `git log --name-only -20` → **woran wird hier real gearbeitet?**
  Welche Pfade ändern sich oft, welche nie?
- Vorhandenes Hook-/CI-Tooling: `.claude/`, `.git/hooks/`, Husky, `.pre-commit-config.yaml`, CI-Workflows.
- `git config user.name` / `user.email` für Attribution.

Gefundene Doku wird **wiederverwendet und im bestehenden Stil fortgeführt** — nie ersetzt, nie dupliziert.

## S2 — Doku-Umfang ableiten (Pflicht, aber leise)

Kein mehrteiliges Interview mehr als Standardfall — der User soll kaum merken, dass der Skill
gerade läuft. Aus S1 ableiten und **annehmen statt fragen**, sofern der Punkt nicht schwer
rückgängig zu machen ist:

1. **Welche Doku-Artefakte werden gepflegt?** Aus S1 ableiten (was existiert, welche Pfade sich in
   der Historie oft ändern) und **bewusst klein wählen** — jedes Artefakt ist Pflegeaufwand, lieber
   drei gepflegte als acht verwaiste. Standard, falls nichts Gegenteiliges erkennbar ist:
   Architektur/Ist-Stand, Entscheidungen, Regeln. Annahme im Abschluss-Report kurz benennen, nicht
   vorab abfragen.
2. **Wer liest das?** Aus dem Kontext ableiten (z. B. explizit als privates/persönliches Repo
   beschrieben → „nur ich"; Repo mit mehreren Contributor:innen in der Historie → „internes Team").
   Nur nachfragen, wenn beide Signale gleichzeitig vorliegen und sich widersprechen.
3. **Was ist doku-relevant, was ist Rauschen?** Aus S1 ableiten: übliche Build-/Dependency-/Log-
   Verzeichnisse als `ignore` vorbelegen, sonst breit als relevant behandeln (leere `relevant`-Liste).
   Nur nachfragen, wenn das Projekt einen ungewöhnlichen Aufbau hat, der sich nicht aus Historie
   oder Manifesten erschließt.
4. **Welche Events sollen auslösen?** Alle vier (`postCommit`, `taskDone`, `stop`, `prePush`) als
   Default setzen, ohne zu fragen — sie sind einzeln in der Config abwählbar, falls sich später
   zeigt, dass eines zu oft/nie feuert.
5. **Härtegrad des Push-Gates — hier immer nachfragen:** blockierend vs. nur Warnung ist die eine
   Stelle in diesem Skill, an der eine falsche Annahme sofort spürbar wird (blockierter `git push`).
   Default-Vorschlag „blockierend", aber als echte Frage stellen, nicht annehmen.

Damit ist S2 inhaltlich abgeschlossen — die einzige tatsächliche Interaktion ist Punkt 5, plus S4b/S5
weiter unten (Hook-Hardwiring und -Aktivierung), die ohnehin schon als Pflichtfragen gelten, weil
sie git-Verhalten verändern.

## S3 — Doku-Struktur anlegen

Nur die in S2 bestätigten Artefakte. Bestehende Dateien weiterverwenden. Nichts überschreiben.
Fehlt ein Artefakt vollständig, wird es mit einem **echten ersten Inhalt** aus S1 angelegt (Ist-Stand
aus Code und Historie), nicht als leeres Template mit Platzhaltern.

Standard-Ablage, falls das Projekt nichts anderes vorgibt:

```
ARCHITECTURE.md                       Ist-Stand + Architektur-Entscheidungen
docs/decisions/QUALITY_DECISIONS.md   Produkt-/Prozess-Entscheidungen
docs/decisions/RULES.md               lebende Regelliste (kein Log)
docs/decisions/.doc-sync.json         Config (committed)
docs/decisions/.last-sync             Sync-Marker (committed, siehe Y6)
```

## S3a — Lesepfad sichern (`CLAUDE.md`) — ohne diesen Schritt ist alles andere wertlos

Der Rest dieses Skills sorgt dafür, dass Claude **schreibt**. Dieser Schritt sorgt dafür, dass ein
**frischer Chat es auch liest** — und das ist der eigentliche Zweck der ganzen Übung: Wissen soll
sessionübergreifend verfügbar sein, ohne dass jemand im selben Chat bleiben oder aktiv danach
fragen muss.

**Claude Code lädt beim Session-Start automatisch nur `CLAUDE.md`.** `ARCHITECTURE.md`,
`docs/decisions/**` und alles andere liest er erst, wenn jemand ausdrücklich danach fragt. Eine
perfekt gepflegte Doku, auf die nichts verweist, wird in einer neuen Session schlicht nicht
bemerkt.

Deshalb im Repo-Root `CLAUDE.md` anlegen oder ergänzen — mit einem **Verweisblock, keiner Kopie**:

```markdown
## Projektwissen — vor der Arbeit lesen

Entscheidungen und Ist-Stand liegen in diesen Dateien. Lies die relevante, bevor du etwas
änderst, das sie betrifft — und halte sie aktuell (Skill `doku-update-sync`):

- `ARCHITECTURE.md` — Ist-Stand, Tech-Stack, Architektur-Entscheidungen samt Begründung
- `docs/decisions/RULES.md` — geltende Regeln (IMMER/NIEMALS). Diese gelten ohne Rückfrage.
- `docs/decisions/QUALITY_DECISIONS.md` — Produkt-/Prozess-Entscheidungen

Automatik: `.claude/hooks/doc-sync-gate` meldet sich nach Commit, Aufgabenende und Session-Ende,
wenn etwas Doku-Relevantes undokumentiert ist, und blockiert `git push`.
```

Regeln dafür:

- **Nur verweisen, nie duplizieren.** Inhalte in `CLAUDE.md` zu kopieren erzeugt eine zweite
  Wahrheit, die sofort zu driften beginnt. Die Liste nennt Dateien und wofür sie zuständig sind.
- **Existiert `CLAUDE.md` bereits**, wird der Block eingefügt, ohne Vorhandenes anzutasten — und
  ohne einen bereits vorhandenen, gleichwertigen Verweis zu verdoppeln.
- **Kurz halten.** `CLAUDE.md` landet in jedem Kontextfenster; jede Zeile darin kostet dauerhaft.
- Der Block kommt in die `docs`-Sektion der Config, damit spätere Syncs ihn mitpflegen, wenn ein
  Doku-Artefakt dazukommt oder wegfällt.

## S4 — Config schreiben

`docs/decisions/.doc-sync.json`, Vorlage: `assets/doc-sync.config.json`. Sie ist die einzige
Wahrheit darüber, was der Hook als relevant betrachtet und welche Dateien gepflegt werden —
kommentiert mit den Antworten aus S2, damit später nachvollziehbar ist, **warum** ein Pfad als
relevant oder irrelevant gilt.

## S5 — Hooks einrichten (nur mit expliziter Zustimmung)

1. **Skript ablegen:** `.claude/hooks/doc-sync-gate.ps1` (Windows) bzw. `.claude/hooks/doc-sync-gate.sh`
   (macOS/Linux). Sprache am vorhandenen Hook-Bestand ausrichten; ohne Vorbild nach dem
   Betriebssystem entscheiden. Bash-Variante ausführbar machen (`chmod +x`).

   **Woher die Dateien kommen — in dieser Reihenfolge:**

   a) **Liegt `assets/` neben dieser SKILL.md?** Dann von dort kopieren. Fertig, nichts laden.

   b) **Sonst von GitHub laden** (Normalfall, wenn der Skill ohne Assets verteilt wurde). Basis-URL:

      ```
      https://raw.githubusercontent.com/fs-rgb/gsf-claude-skills/main/doku-update-sync/assets/
      ```

      Gebraucht werden: `doc-sync-gate.ps1` **oder** `doc-sync-gate.sh` (je nach Betriebssystem),
      `doc-sync.config.json`, `settings-hooks.json`. **Das Geladene vor dem Ablegen prüfen:** die
      Skripte müssen mit `#!` oder einem Kommentarblock beginnen, die JSON-Dateien müssen parsen.
      GitHub liefert bei 404 eine Textseite mit Status 200-Anmutung — ungeprüft abgelegt hätte man
      dann einen Hook, der nie feuert.

   c) **Scheitert auch das** (kein Netz, Proxy, Repo umbenannt): Dateien **selbst erzeugen** nach
      **Anhang A** dieser Datei. Das Setup wird nie mit „Download fehlgeschlagen" abgebrochen.

   Im Abschluss-Report **benennen, welcher Weg genommen wurde** — bei (c) zusätzlich, dass die
   Skripte selbst erzeugt wurden und ein späterer Abgleich mit dem Original sinnvoll ist.
2. **Registrieren** in `<repo>/.claude/settings.json` — **committed**, nicht `settings.local.json`,
   sonst greift bei Kolleginnen und Kollegen nichts. Vorlage: `settings-hooks.json` (siehe Punkt 1).
   Existiert die Datei bereits, wird der `hooks`-Block **hineingemischt**, nie ersetzt.
3. **Skill mitliefern:** diesen Skill nach `<repo>/.claude/skills/doku-update-sync/` kopieren und
   mitcommitten — sonst laufen die Hooks im Team ins Leere, weil der Skill dort nicht installiert
   ist. Falls `decision-records` genutzt wird, ebenso kopieren. Die Kopie trägt in der Config unter
   `skillSource` ihre Herkunft (`https://github.com/fs-rgb/gsf-claude-skills`), damit ein Update
   auffindbar bleibt.
4. **Vorschlag zeigen, auf Bestätigung warten.** Nie ungefragt anlegen oder aktivieren.
5. **Smoke-Test:** Skript einmal manuell mit leerem stdin aufrufen und prüfen, dass es bei sauberem
   Zustand mit Exit 0 und ohne Ausgabe endet. Ein Hook, der beim ersten echten Commit unerwartet
   feuert oder crasht, wird abgeschaltet und ist damit wertlos.

## S6 — Regel verankern

In `docs/decisions/RULES.md` eine imperative Zeile ergänzen, die den Mechanismus selbst festhält —
damit auch ohne Hook (fremde Umgebung, abgeschaltete Hooks) die Erwartung dokumentiert ist:

```markdown
- IMMER nach abgeschlossener Aufgabe und vor `git push` prüfen, ob die Doku den Ist-Stand noch
  trifft — automatisiert über `doku-update-sync` (`.claude/hooks/doc-sync-gate`).
```

Danach: Abschluss-Report (siehe unten) und `.last-sync` setzen.

---

# Sync-Modus

Läuft bei jedem Hook-Feuern. **Hier wird standardmäßig nicht gefragt und nicht kommentiert.**

## Y1 — Delta bestimmen

`docs/decisions/.last-sync` liefert den zuletzt geprüften Commit. Geändert seither:

```
git diff --name-only <last-sync-sha> HEAD        # committed
git diff --name-only                             # working tree
git ls-files --others --exclude-standard         # untracked
```

Kein Marker vorhanden → gesamte Historie als Delta behandeln, aber Y2 entscheidet trotzdem über Relevanz.

## Y2 — Relevanz prüfen (das Filter, das den Skill erträglich macht)

Delta gegen `relevant` / `ignore` aus der Config filtern. Änderungen an den Doku-Dateien selbst
zählen **nie** als Auslöser (sonst Endlosschleife).

**Bleibt nichts übrig → sofort und vollständig stumm beenden.** Keine Meldung, kein „nichts zu tun",
kein Eintrag. Der Skill darf sich nicht bemerkbar machen, wenn er nichts beizutragen hat — das ist
die Voraussetzung dafür, dass die Hooks eingeschaltet bleiben.

## Y3 — Delta einordnen

Für jede relevante Änderung entscheiden, welcher Typ vorliegt:

| Typ | Erkennungsmerkmal | Behandlung |
|---|---|---|
| **Faktisches Update** | Was da ist, hat sich geändert: neues Modul/Workflow, neue Top-Level-Dependency, geändertes Schema/Datenmodell, umbenannte Komponente, entfernter Teil | Y4 — **still schreiben** |
| **Begründungsbedürftige Entscheidung** | Kurswechsel, Alternative verworfen, Tech-Stack-Wahl, bewusste Abweichung von einem bestehenden Eintrag | Y5 — an `decision-records` übergeben |
| **Irrelevant** | Formatierung, Refactoring ohne Strukturwirkung, Testdaten | ignorieren, nicht erwähnen |

Im Zweifel zwischen faktisch und begründungsbedürftig: **faktisch behandeln**. Lieber ein
knapper korrekter Ist-Stand-Satz als eine unnötige Rückfrage — der Ask-until-clear-Loop gehört
`decision-records` und ist dort teuer erkauft.

## Y4 — Faktisches Update schreiben (ohne Rückfrage)

In die zuständige Datei aus der Config, im dort vorhandenen Stil, so knapp wie möglich:

- **Ist-Stand-Abschnitte werden fortgeschrieben**, nicht angehängt — was nicht mehr stimmt, wird
  korrigiert, mit Datum am Abschnitt (`Stand: YYYY-MM-DD`).
- **Entscheidungs-Einträge bleiben unangetastet.** Sie sind historische Fakten; ein überholter
  Eintrag wird nie umgeschrieben, sondern durch einen neuen mit Verweis abgelöst — und das ist
  Sache von `decision-records`, nicht dieses Skills.
- Keine Füllsätze, keine Zusammenfassung dessen, was der Diff schon zeigt. Dokumentiert wird, was
  man **nicht** aus dem Code ablesen kann: Zweck, Rolle im System, Verbindung zu anderen Teilen.

## Y4a — Sonderfall Push-Gate: durchlaufen, nicht nachfragen

Wurde der Lauf durch den blockierten `git push` ausgelöst, gilt zusätzlich:

1. **Keine Bestätigungsfrage.** Nicht „soll ich den Sync jetzt machen?" — der Auftrag steht in der
   Hook-Meldung, die den Push blockiert hat. Direkt mit Y1 beginnen.
2. **Doku committen.** Die geschriebenen Änderungen und `docs/decisions/.last-sync` in einem Commit
   festhalten (siehe Y6), sonst bleibt der Gate zu und der Push nimmt die Doku nicht mit.
3. **Push unverändert wiederholen** — dasselbe Kommando, ohne Bypass. Der Gate ist jetzt offen,
   weil das Delta seit `.last-sync` leer ist.
4. **Den Push nicht für eine Rückfrage anhalten.** Fehlt zu einer Änderung die Begründung, kommt sie
   nach Y5 als Platzhalter unter `## Offen / noch zu begründen` und wird **nach** dem Push in einem
   Satz erwähnt. Der Ask-until-clear-Loop von `decision-records` läuft dann später, nicht mitten im
   Push.
5. **Den Bypass nicht selbst wählen.** `DOC_SYNC_SKIP=1` gehört dem User. Ihn zu benutzen, um den
   Gate schneller loszuwerden, hebelt genau den Mechanismus aus, für den er gebaut wurde.

Bleibt der Gate nach dem Sync zu, ist etwas kaputt (Marker nicht committet, Doku-Pfad nicht in der
Config) — das melden statt den Bypass zu ziehen oder es erneut zu versuchen.

## Y5 — Entscheidung erkannt → übergeben

`decision-records` aufrufen, mit dem konkreten Signal als Kontext („neue Dependency X ersetzt Y",
„Modul Z entfernt"). Dort läuft der Ask-until-clear-Loop. Ist der User nicht erreichbar (Hook-Lauf
ohne Interaktionsmöglichkeit): die offene Frage in `docs/decisions/QUALITY_DECISIONS.md` unter
einem Abschnitt `## Offen / noch zu begründen` als Platzhalter mit Datum und Signal festhalten,
statt sie verfallen zu lassen. Nie eine Begründung erfinden.

## Y6 — Marker aktualisieren

`docs/decisions/.last-sync` mit aktuellem `HEAD`-SHA und Zeitstempel schreiben — **nur wenn
tatsächlich ein Lauf stattgefunden hat.** Die Datei wird **mitcommittet**: sie bedeutet „die Doku
ist auf dem Stand dieses Commits" und ist damit eine geteilte Tatsache, nicht lokaler Zustand.
Sonst würde jede neu klonende Person mit der kompletten Historie als vermeintlichem Delta starten.

**Marker und Doku-Änderung gehören in denselben Commit.** Bleiben sie unversioniert liegen, klont
das Team den alten Marker und bekommt Änderungen gemeldet, die längst dokumentiert sind — der
Hook wirkt dann kaputt und wird abgeschaltet. Beim Anbieten des Commits also immer beides
zusammen vorschlagen. Der SHA zeigt dabei auf den Commit **vor** dem Doku-Commit; das ist
korrekt, weil genau dieser Stand geprüft wurde.

Bei Merge-Konflikten auf dieser Datei gilt: den **älteren** SHA behalten. Lieber einmal zu viel
prüfen als eine Lücke überspringen.

**Sonderfall: Repo ohne jeden Commit** (frisches Setup, `git rev-parse HEAD` schlägt fehl). Dann
`"sha": null` schreiben und **zwingend `reviewedAt` auf die tatsächliche aktuelle Uhrzeit setzen**
(z. B. `date -u +%Y-%m-%dT%H:%M:%SZ`), nie auf Tagesbeginn oder einen anderen Platzhalter — das
Gate-Skript vergleicht `reviewedAt` gegen die `LastWriteTime` jeder Datei, und ein zu früher
Zeitstempel lässt frisch angelegte Setup-Dateien fälschlich wieder als „seit dem Sync geändert"
gelten, wodurch der Hook bei jedem weiteren Ereignis erneut feuert, obwohl nichts Neues passiert
ist. Sobald der erste echte Commit existiert, ersetzt der nächste Lauf `sha: null` durch die
richtige SHA.

## Y7 — Rückmeldung

Nur wenn tatsächlich etwas geschrieben wurde: **ein Satz**, welche Datei und was. Kein Report, kein
Aufzählungsblock, keine Nachfrage, ob es so recht war. Wurde an `decision-records` übergeben,
übernimmt dessen Report.

---

## Was dabei NIE passiert

- Sich im Sync-Modus bemerkbar machen, ohne dass es relevantes Delta gab.
- Im Sync-Modus fragen, was aus dem Diff ableitbar ist.
- Eine Begründung („Warum", „Was nicht") erfinden, statt an `decision-records` zu übergeben oder als
  offen zu markieren.
- Bestehende Entscheidungs-Einträge überschreiben oder löschen — auch nicht, wenn sie überholt sind.
- Doku-Artefakte anlegen, die weder aus S1 ableitbar noch offensichtlich sinnvoll sind.
- In S2 eine Rückfrage-Kaskade über Punkte 1–4 starten, obwohl eine Annahme aus S1 gereicht hätte
  — Punkt 5 (Push-Gate-Härtegrad) und S4b/S5 (Hook-Hardwiring/-Aktivierung) bleiben die einzigen
  planmäßigen Rückfragen im Setup-Modus.
- Hooks anlegen, aktivieren oder committen ohne explizite Zustimmung.
- Die Doku-Struktur anlegen, ohne den Lesepfad in `CLAUDE.md` zu sichern (S3a) — eine Doku, auf
  die nichts verweist, wird in einer neuen Session nicht gelesen und war damit umsonst.
- Doku-Inhalte nach `CLAUDE.md` kopieren statt dorthin zu verweisen.
- Hooks in `settings.local.json` statt `settings.json` registrieren — das bricht die Team-Verteilung
  still und fällt erst auf, wenn im Team nie etwas passiert.
- Den Skill ins Repo kopieren, ohne die Herkunft (`skillSource`) zu vermerken.
- `.last-sync` aktualisieren, ohne dass ein Lauf stattgefunden hat.
- Beim blockierten Push nachfragen, ob der Sync laufen soll (Y4a) — er läuft.
- Den Push-Gate-Bypass selbst wählen, um einen blockierten Push schneller loszuwerden. Er gehört
  dem User; Claude benennt ihn höchstens, wenn der Sync nachweislich nichts zu tun findet.
- Ein heruntergeladenes Hook-Skript ungeprüft ablegen — eine Fehlerseite als Skript feuert nie und
  fällt monatelang nicht auf.
- Das Setup abbrechen, weil der Download scheiterte. Dafür gibt es Anhang A.

## Abschluss-Report (nur Setup-Modus)

Welche Doku-Artefakte jetzt gepflegt werden und warum genau diese, was als doku-relevant gilt,
welche Hook-Events aktiv sind und welches davon blockiert, wohin der Skill kopiert wurde, und was
als Nächstes committet werden muss.

---

# Anhang A — Spezifikation des Gate-Skripts (Fallback ohne Download)

Nur nötig, wenn weder `assets/` daneben liegt noch der Download klappt. Ziel ist kein Nachbau
Zeile für Zeile, sondern ein Skript mit **exakt diesem Verhalten**. Sprache: PowerShell unter
Windows, sonst Bash.

**Aufruf:** `doc-sync-gate <check|push>`, Hook-Payload als JSON auf stdin.

**Ablauf, in dieser Reihenfolge — jeder Schritt bricht bei Nichtzutreffen stumm mit Exit 0 ab:**

1. stdin als JSON lesen. Unlesbar → weiterarbeiten mit leerem Payload, nicht abbrechen.
2. `stop_hook_active == true` → Exit 0. (Schleifenschutz: sonst feuert der Stop-Hook endlos.)
3. Nach `tool_name` verzweigen:
   - `Bash`/`PowerShell`: im Modus `push` muss `tool_input.command` auf `git push` passen
     (Wortgrenze, auch nach `;`, `&&`, `|`, `(`), sonst Exit 0; enthält das Kommando
     `DOC_SYNC_SKIP` → Exit 0 (bewusster Bypass, wird im **Kommandotext** erkannt, nicht in der
     Prozessumgebung — die Variable erreicht den Hook nie). Im Modus `check` analog auf `git commit`.
   - `TodoWrite`: nur im Modus `check`; Exit 0, solange irgendein Todo `status != "completed"` hat.
   - Kein `tool_name` (Stop-Hook) → weiter.
4. Repo-Wurzel via `git rev-parse --show-toplevel`; kein Repo → Exit 0.
5. `docs/decisions/.doc-sync.json` fehlt → Exit 0. Ein Repo ohne Setup wird nie behelligt.
6. Event bestimmen (`taskDone` / `prePush` / `stop` / `postCommit`) und in `events` nachsehen;
   steht dort `false` → Exit 0.
7. Delta sammeln aus `git diff --name-only <sha>` (SHA aus `.last-sync`; existiert er nicht mehr —
   Rebase, Force-Push — auf `git diff --name-only HEAD` zurückfallen), `git diff --name-only --cached`
   und `git ls-files --others --exclude-standard`. Pfadtrenner auf `/` normalisieren.
8. Ist in `.last-sync` ein `reviewedAt` gesetzt, nur Dateien behalten, deren Änderungszeit **danach**
   liegt (gelöschte Dateien immer behalten). Ohne das feuert ein dauerhaft schmutziger Working Tree
   bei jedem Ereignis erneut.
9. Filtern, in dieser Reihenfolge: alle Pfade aus `docs` der Config plus `docs/decisions/**`
   verwerfen (sonst löst der Sync sich selbst aus), dann `ignore`, dann — falls `relevant` nicht
   leer ist — nur Treffer aus `relevant` behalten. Glob-Regeln: `*` ohne `/`, `**` beliebig tief,
   ein abschließender `/` wirkt wie `/**`.
10. Nichts übrig → Exit 0, **ohne jede Ausgabe**.
11. Ausgabe:
    - Modus `push` und `pushGate != "warn"`: JSON auf stdout, Exit 0 —
      `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
      "permissionDecisionReason":"<Text>"}}`
    - sonst: `<Text>` auf **stderr**, Exit **2** (so erreicht der Text Claude).
    - `<Text>` nennt Anlass und die geänderten Dateien (auf ~12 gekürzt) und beauftragt Claude,
      `doku-update-sync` im Sync-Modus **sofort und ohne Rückfrage** auszuführen; im Push-Fall
      zusätzlich: Doku samt `.last-sync` committen, Push unverändert wiederholen, für eine fehlende
      Begründung den Push nicht anhalten. Bypass nennen, aber als Sache des Users.

**Zwei Fallstricke, die das Skript sonst stillschweigend unbrauchbar machen:**

- **PowerShell:** `$ErrorActionPreference` **nicht** auf `Stop` setzen. Windows PowerShell verpackt
  jede stderr-Zeile eines nativen Programms in einen Fehler, und `git` warnt routinemäßig
  (`LF will be replaced by CRLF`). Mit `Stop` wird daraus ein Abbruch — das Skript endet stumm mit
  Exit 0 und feuert nie, ohne dass es auffällt. `Continue` verwenden, Fehler stattdessen gezielt
  per `try/catch` und `$LASTEXITCODE` behandeln.
- **Ausgabetexte rein ASCII halten** (`ae`/`oe`/`ue`, `-` statt Gedankenstrich). Sonst kommt der
  Text durch die Konsolen-Codepage verstümmelt bei Claude an.

**Meldungstexte nie erfinden, sondern sinngemäß wie oben formulieren** — sie sind der eigentliche
Wirkmechanismus: Der Hook blockiert nur, gearbeitet wird aufgrund dieses Textes.

**Smoke-Test nach dem Erzeugen** (Pflicht, siehe S5.5): einmal mit leerem stdin bei sauberem
Repo-Zustand aufrufen — muss Exit 0 und **keine** Ausgabe liefern.
