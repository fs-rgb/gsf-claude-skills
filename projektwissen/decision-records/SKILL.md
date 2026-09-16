---
name: decision-records
description: >
  Legt Decision Record Documents (Architektur-Entscheidungen, Gesamtprojektarchitektur, wichtige
  qualitative Entscheidungen) für ein Projekt an und pflegt sie — portabel, funktioniert in jedem
  Projekt (neu gestartet oder bestehend). Nutze diesen Skill, wenn ein Projekt noch keine
  Decision-Record-Struktur hat (Bootstrap), wenn gerade eine Architektur-/Tech-Stack-/Prozess-/
  qualitative Entscheidung getroffen wurde und festgehalten werden soll, wenn noch kein
  Automatisierungs-Hook für künftige Syncs existiert, oder wenn Claude ein entscheidungswürdiges
  Signal erkennt (neue Dependency, neues Modul, Kurswechsel) und einen Sync vorschlägt. Klärt dabei
  aktiv offene Fragen, bevor etwas geschrieben wird (Ask-until-clear). Die Automatisierung baut
  dieser Skill nicht selbst: dafür übergibt er an den Schwesterskill doku-update-sync, der die
  Hooks einrichtet, sie für beide betreibt und die übrige Doku aktuell hält.
---

# Skill: Decision Records

Hält fest, **wer wann was warum entschieden hat** — und was bewusst nicht gemacht wurde. Wissen aus
Sessions soll nicht verloren gehen, nur weil es nie irgendwo strukturiert landet. Funktioniert in
jedem Projekt, unabhängig von dessen konkreter Doku-/Hook-Technologie.

## Schritt 1 — Zustand erkennen

Im Zielprojekt nach vorhandenen Decision-Record-Kandidaten suchen: `ARCHITECTURE.md` (Root),
`docs/ARCHITECTURE.md`, `docs/decisions/**`, `docs/adr/**`, `DECISIONS.md`. Gefundene Dateien
**wiederverwenden und im bestehenden Stil fortführen** — nie duplizieren oder ersetzen. Nichts
gefunden → Schritt 2 läuft im Bootstrap-Modus (Interview über Zielbild, Tech-Stack, bereits
getroffene Entscheidungen, statt nur eine einzelne Entscheidung abzufragen).

## Schritt 2 — Kategorie bestimmen

Default-Taxonomie bewusst klein (kein Over-Engineering — neue Kategorien nur nach Rückfrage, wenn
ein Eintrag nachweislich in keine bestehende passt):

| Kategorie | Ziel-Datei | Inhalt |
|---|---|---|
| Architektur | Root-`ARCHITECTURE.md` (wiederverwenden falls vorhanden, sonst dort neu anlegen) | Tech-Stack, System-/Datenmodell, Modulgrenzen — das „Warum" |
| Qualitativ/Prozess | `docs/decisions/QUALITY_DECISIONS.md` | Produkt-/UX-/Prozess-Entscheidungen, die keine Architektur sind |
| Regeln | `docs/decisions/RULES.md` | **kein Log** — lebende Liste aktuell geltender Regeln, siehe Schritt 4a |

## Schritt 3 — Klärungs-Loop (Ask-until-clear)

Bevor irgendetwas geschrieben wird: mit `AskUserQuestion` (oder gleichwertigem Interaktions-Tool
der jeweiligen Umgebung) gezielte, nicht-offensichtliche Rückfragen stellen — Alternativen,
Trade-offs, „was bewusst nicht". Multiple-Choice anbieten, wo sinnvoll. Wiederholen, bis keine
offene Frage mehr bleibt. Eine Entscheidung erst als vollständig behandeln, wenn Alternative und
Ablehnungsgrund benennbar sind — sonst weiterfragen statt zu raten.

## Schritt 4 — Eintrag schreiben (Architektur/Qualitativ)

Festes Template, um Attribution ergänzt:

```markdown
## <Titel>

**Entscheidung (YYYY-MM-DD, <Git-Name> <<Git-Email>>):** ...

**Warum:**
- ...

**Was nicht:**
- ...

**Konsequenz:** (optional)
```

Autor/Datum kommen automatisch aus `git config user.name` / `user.email` + Systemdatum — kein
manueller Zusatzschritt. Kein Git verfügbar → einmalig nachfragen, nie raten. Bestehende Einträge
werden nie überschrieben/gelöscht — nur angehängt bzw. mit „Entscheidung X revidiert am Y"
fortgeschrieben.

## Schritt 4a — Regel ableiten (falls zutreffend)

Nicht jede Entscheidung ist eine Regel — viele sind einmalige historische Fakten (z. B. „warum
Neubau statt Reparatur"). Schreibt die Entscheidung aber ein **wiederkehrendes Verhalten** vor
(z. B. „Secrets werden nie überschrieben", „Migrationen immer erst in DEV testen"), zusätzlich eine
kurze, imperative Regelzeile in `docs/decisions/RULES.md` ergänzen/aktualisieren — NIEMALS/IMMER-
Sprache, mit Verweis zurück auf den auslösenden Entscheidungs-Eintrag statt die Begründung zu
duplizieren.

## Schritt 4b — Hart verdrahten? (Pflichtfrage, kein Ausnahmefall)

Für **jede** neu geschriebene/aktualisierte Regel aus Schritt 4a immer nachfragen, ob sie
zusätzlich hart per Hook erzwungen werden soll (Default-Option: „Nein, vorerst nur dokumentiert").
Diese Nachfrage entfällt nie — auch nicht, wenn vorherige Regeln in derselben Session soft blieben,
und nicht bei Regeln, die „offensichtlich klein" wirken.

Bei „Ja": zuerst das im Zielprojekt vorhandene Hook-/CI-Tooling erkennen (`.git/hooks/`,
Husky-Config in `package.json`, `.pre-commit-config.yaml`, projekteigene PowerShell-/Bash-Hooks,
o. ä. — Technologie des jeweiligen Projekts übernehmen, nichts fest annehmen) und einen minimalen
Block-Hook vorschlagen: blockiert + klare Fehlermeldung + dokumentierter Bypass — nie stilles
Scheitern. Den Hook nie ohne explizite Zustimmung tatsächlich anlegen/aktivieren.

## Schritt 5 — Automatisierung: an `doku-update-sync` übergeben (Pflicht, kein Ausnahmefall)

**Das ist die Lücke, die diesen Skill zahnlos machen würde:** ohne echten Hook läuft er genau
einmal und wird danach nie wieder beachtet, weil eine neue Session vom vorherigen Lauf nichts weiß
und niemand aktiv daran denkt, ihn erneut aufzurufen.

**Diesen Mechanismus baut dieser Skill nicht selbst** — dafür gibt es den Schwesterskill
`doku-update-sync`. Er richtet die Hooks ein, betreibt sie für beide Skills und hält darüber hinaus
die restliche Doku (Ist-Stand, Architekturbeschreibung, Setup) aktuell.

**Anders als Schritt 4b:** dort ging es um das harte Verdrahten *einer einzelnen* abgeleiteten
Regel. Hier geht es um den Sync-**Mechanismus selbst** — ob künftige, noch unbekannte Entscheidungen
überhaupt automatisch bemerkt werden.

### Wann übergeben

Prüfen, ob im Zielprojekt `docs/decisions/.doc-sync.json` existiert.

- **Existiert nicht** → `doku-update-sync` aufrufen. Er läuft dann in seinem Setup-Modus: Interview
  über den gewünschten Doku-Umfang, Relevanz-Filter, Hook-Events, Installation ins Repo. Diese
  Übergabe ist **Pflicht bei jedem Lauf, solange noch kein Mechanismus existiert** — beim Bootstrap
  genauso wie bei jeder späteren Entscheidung, nicht nur beim allerersten Mal. Auch dann erneut
  vorschlagen, wenn der User beim letzten Lauf abgelehnt hat (erneut fragen ist erlaubt,
  Stillschweigen nicht).
- **Existiert** → nichts weiter tun. Der Mechanismus läuft; dieser Skill aktualisiert nur noch
  `docs/decisions/.last-sync` am Ende seines Laufs (siehe unten) und meldet im Report, dass die
  Automatisierung aktiv ist.

`doku-update-sync` ist selbst dafür zuständig, dass nichts ohne explizite Zustimmung angelegt,
aktiviert oder committet wird. Dieser Skill trifft dazu keine eigenen Entscheidungen und legt
insbesondere **keine eigenen Hooks** an — zwei konkurrierende Hook-Mechanismen im selben Repo sind
schlimmer als keiner.

### Ist `doku-update-sync` nicht verfügbar

Kein Grund, die Frage zu überspringen. Der Skill fehlt, wenn er weder in der Skill-Liste auftaucht
noch unter `<repo>/.claude/skills/doku-update-sync/` liegt. Dann in dieser Reihenfolge:

1. Im aktuellen Repo unter `.claude/skills/doku-update-sync/` nachsehen — dorthin kopiert ihn sein
   eigenes Setup, er ist dann oft schon da.
2. Sonst von der Quelle holen: **https://github.com/fs-rgb/gsf-claude-skills**, roh unter
   `https://raw.githubusercontent.com/fs-rgb/gsf-claude-skills/main/projektwissen/doku-update-sync/SKILL.md`.
   Nach `<repo>/.claude/skills/doku-update-sync/SKILL.md` ablegen und dessen Setup-Modus ausführen.
   Das Geladene vorher prüfen: es muss mit `---` und `name: doku-update-sync` beginnen — eine
   Fehlerseite kommt sonst unbemerkt als Skill im Repo an.
3. Klappt auch das nicht (kein Netz, Proxy), offen benennen — **aber keine eigenen Hooks bauen**.

Erst wenn der User ausdrücklich keinen Automatismus will, gilt „bewusst nur manuell" — und auch das
gehört so in den Abschluss-Report.

### Umgekehrte Richtung

Läuft `doku-update-sync` im Sync-Modus und stößt auf eine **begründungsbedürftige** Änderung
(Kurswechsel, verworfene Alternative, Tech-Stack-Wahl), ruft er diesen Skill auf und liefert das
erkannte Signal als Kontext mit. Der Klärungs-Loop aus Schritt 3 läuft dann ganz normal — er wird
nie übersprungen, nur weil der Auslöser automatisch war. Pro Lauf höchstens eine Übergabe je
Richtung, damit sich die beiden Skills nicht gegenseitig aufrufen.

### Sync-Marker

Am Ende jedes abgeschlossenen Laufs `docs/decisions/.last-sync` aktualisieren — JSON mit aktuellem
`HEAD`-SHA und Zeitstempel, Format und Semantik definiert `doku-update-sync` (Schritt Y6). Der Hook
vergleicht nur das Delta seit diesem Marker; ohne Aktualisierung meldet er dieselben Änderungen
endlos erneut. Die Datei wird **mitcommittet**. Nie aktualisieren, ohne dass tatsächlich ein Lauf
stattgefunden hat.

## Schritt 6 — Ergänzender In-Session-Hinweis

Zusätzlich zum Hook (nicht als Ersatz dafür): innerhalb einer laufenden Session weiterhin heuristisch
auf entscheidungswürdige Signale achten — neue Top-Level-Dependency, neues Modul/Schema/
Infra-Ressource, Widerspruch zu einem bestehenden Eintrag, explizite Entscheidungs-Sprache im Chat
(„wir haben entschieden", „ab jetzt nutzen wir X statt Y") — und proaktiv vorschlagen, den Skill
auszuführen. Das deckt die Lücke zwischen zwei Hook-Auslösungen ab, ersetzt den Hook aber nicht.

## Was dabei NIE passiert

- Bestehende Einträge überschreiben oder löschen.
- Eine neue Kategorie-Datei ohne Rückfrage anlegen.
- Den Klärungs-Loop (Schritt 3) überspringen, nur weil die Entscheidung „offensichtlich" wirkt.
- Attribution erfinden, wenn die Git-Identität nicht ermittelbar ist.
- Die Hart-Verdrahten-Frage aus Schritt 4b überspringen.
- Die Übergabe an `doku-update-sync` aus Schritt 5 überspringen, solange noch kein Mechanismus
  existiert — auch nicht, wenn der User beim letzten Lauf bereits „Nein" gesagt hat (erneut fragen
  ist erlaubt, Stillschweigen nicht).
- Eigene Hooks anlegen, statt an `doku-update-sync` zu übergeben — zwei konkurrierende
  Hook-Mechanismen im selben Repo sind schlimmer als keiner.
- Einen Hook committen/aktivieren ohne explizite Zustimmung.
- Den `.last-sync`-Marker aktualisieren, ohne dass tatsächlich ein Lauf stattgefunden hat.
- Den Klärungs-Loop überspringen, nur weil der Auslöser eine automatische Übergabe von
  `doku-update-sync` war statt einer direkten Anfrage des Users.

## Abschluss-Report

Welche Datei(en)/welcher Eintrag geschrieben wurde, ob eine Regel in RULES.md ergänzt wurde, ob/wie
sie hart verdrahtet wurde (oder bewusst soft blieb), und **ob der Doku-Sync-Mechanismus** (via
`doku-update-sync`) jetzt aktiv ist — welche Events ihn auslösen, oder ob der User bewusst bei „nur
manuell" geblieben ist.
