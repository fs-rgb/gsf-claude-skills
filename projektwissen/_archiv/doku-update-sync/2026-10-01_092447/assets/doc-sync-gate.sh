#!/usr/bin/env bash
# doc-sync-gate.sh — Teil des Skills "doku-update-sync".
# POSIX-/macOS-/Linux-Variante von doc-sync-gate.ps1. Siehe dort fuer die Doku.
#
#   ./doc-sync-gate.sh check   nach git commit / TodoWrite-Abschluss / Session-Ende
#   ./doc-sync-gate.sh push    vor git push (blockiert)
#   ./doc-sync-gate.sh edit    nach Edit/Write/NotebookEdit, braucht KEIN Git -
#                              prueft nur die eine bearbeitete Datei direkt gegen
#                              relevant/ignore, kein git diff. Einziger Modus, der
#                              auch ohne Versionskontrolle funktioniert (reine
#                              Word-/PDF-Ablage); check/push/stop bleiben git-
#                              gebunden, es gibt dort also keinen Session-Ende-
#                              Backstop ohne Git, nur den Sofort-Hinweis.
#
# Benoetigt jq. Bypass fuer den Push-Gate: DOC_SYNC_SKIP=1 git push

set -uo pipefail

MODE="${1:-check}"
silent() { exit 0; }

# Ohne jq ist der gesamte Mechanismus wirkungslos. Mit Exit 0 wuerde das nie auffallen -
# eine stderr-Zeile bei Exit 0 erreicht Claude nicht, der Hook waere monatelang stumm tot.
# Deshalb: im push-Modus Exit 0 (eine fehlende Abhaengigkeit darf nie einen Push blockieren),
# im check-Modus Exit 2, damit der defekte Zustand sichtbar wird.
if ! command -v jq >/dev/null 2>&1; then
  [ "$MODE" = "push" ] && exit 0
  echo "[doku-update-sync] Hook wirkungslos: jq ist nicht installiert (brew install jq bzw. apt install jq). Bis dahin prueft nichts, ob die Doku zum Code passt." >&2
  exit 2
fi

PAYLOAD="$(cat 2>/dev/null || true)"
jqp() { [ -n "$PAYLOAD" ] && printf '%s' "$PAYLOAD" | jq -r "$1" 2>/dev/null || true; }

# Schleifenschutz fuer den Stop-Hook
[ "$(jqp '.stop_hook_active // false')" = "true" ] && silent

TOOL="$(jqp '.tool_name // ""')"
CMD="$(jqp '.tool_input.command // ""')"

matches() {  # $1 = Pfad, stdin = Muster (ein Glob pro Zeile)
  local pfad="$1" m
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    case "$m" in */) m="${m}**" ;; esac
    # shellcheck disable=SC2254
    case "$pfad" in $m) return 0 ;; esac
    case "$m" in
      */'**') case "$pfad" in "${m%/**}"/*) return 0 ;; esac ;;
    esac
  done
  return 1
}

# ------------------------------------------------------------------ Edit-Modus
# Eigener, git-unabhaengiger Zweig: prueft nur die eine gerade bearbeitete Datei,
# kein git diff noetig. Deshalb VOR dem git-gebundenen Rest und mit eigenem Exit.
if [ "$MODE" = "edit" ]; then
  case "$TOOL" in Edit|Write|NotebookEdit) ;; *) silent ;; esac

  FILE_PATH="$(jqp '.tool_input.file_path // ""')"
  [ -n "$FILE_PATH" ] || silent

  # Root: git bevorzugt (falls vorhanden), sonst das Arbeitsverzeichnis des Hooks -
  # das ist bei Claude Code immer der Projektordner, auch ohne Git.
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$ROOT" ] || ROOT="$PWD"

  CONFIG="$ROOT/docs/decisions/.doc-sync.json"
  [ -f "$CONFIG" ] || silent

  [ "$(jq -r '.events.onEdit // true' "$CONFIG" 2>/dev/null)" = "false" ] && silent

  case "$FILE_PATH" in
    "$ROOT"/*) REL="${FILE_PATH#"$ROOT"/}" ;;
    *)         REL="$FILE_PATH" ;;
  esac

  DOCS_ED="$(jq -r '(.docs // {}) | to_entries[] | .value' "$CONFIG" 2>/dev/null)
docs/decisions/**"
  IGNORE_ED="$(jq -r '(.ignore // [])[]' "$CONFIG" 2>/dev/null)"
  RELEVANT_ED="$(jq -r '(.relevant // [])[]' "$CONFIG" 2>/dev/null)"

  printf '%s\n' "$DOCS_ED" | matches "$REL" && silent
  printf '%s\n' "$IGNORE_ED" | matches "$REL" && silent
  if [ -n "$RELEVANT_ED" ]; then
    printf '%s\n' "$RELEVANT_ED" | matches "$REL" || silent
  fi

  # Drosselung: pro Sync-Zyklus (reviewedAt aus .last-sync) nur einmal je Datei
  # nudgen - sonst meldet sich der Hook bei jeder einzelnen Bearbeitung erneut.
  MARKER_ED="$ROOT/docs/decisions/.last-sync"
  REVIEWED_ED=""
  [ -f "$MARKER_ED" ] && REVIEWED_ED="$(jq -r '.reviewedAt // ""' "$MARKER_ED" 2>/dev/null)"

  STATE_DIR="$ROOT/.claude/hooks"
  STATE_PATH="$STATE_DIR/.doc-sync-onedit.json"
  PREV_ED=""
  [ -f "$STATE_PATH" ] && PREV_ED="$(jq -r --arg f "$REL" '.[$f] // ""' "$STATE_PATH" 2>/dev/null)"
  [ "$PREV_ED" = "$REVIEWED_ED" ] && silent

  mkdir -p "$STATE_DIR" 2>/dev/null
  if [ -f "$STATE_PATH" ]; then
    jq --arg f "$REL" --arg r "$REVIEWED_ED" '.[$f] = $r' "$STATE_PATH" > "$STATE_PATH.tmp" 2>/dev/null \
      && mv "$STATE_PATH.tmp" "$STATE_PATH"
  else
    jq -n --arg f "$REL" --arg r "$REVIEWED_ED" '{($f): $r}' > "$STATE_PATH" 2>/dev/null
  fi

  cat >&2 <<EOF
[doku-update-sync] '$REL' bearbeitet - laut Konfiguration doku-relevant.

Kein Git-Hook noetig fuer diesen Hinweis: pruefe direkt jetzt, in derselben Aufgabe, ob die
zugehoerige Beschreibung (docs/decisions/.doc-sync.json -> "docs") noch stimmt, und schreibe
faktisch Ableitbares still fort. Ist nichts zu aendern, einfach weiterarbeiten - dieser Hinweis
erscheint fuer diese Datei erst nach dem naechsten echten Sync erneut.
EOF
  exit 2
fi

if [ "$TOOL" = "Bash" ] || [ "$TOOL" = "PowerShell" ]; then
  if [ "$MODE" = "push" ]; then
    printf '%s' "$CMD" | grep -Eq '(^|[;&|([:space:]])git[[:space:]]+push' || silent
    printf '%s' "$CMD" | grep -q 'DOC_SYNC_SKIP' && silent   # bewusster, sichtbarer Bypass
  else
    printf '%s' "$CMD" | grep -Eq '(^|[;&|([:space:]])git[[:space:]]+commit' || silent
  fi
fi

# TodoWrite zaehlt erst als "Aufgabe fertig", wenn nichts mehr offen ist.
if [ "$TOOL" = "TodoWrite" ]; then
  [ "$MODE" = "push" ] && silent
  OFFEN="$(jqp '[.tool_input.todos[]? | select(.status != "completed")] | length')"
  [ -z "$OFFEN" ] && silent
  [ "$OFFEN" != "0" ] && silent
fi

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || silent
[ -n "$REPO" ] || silent

CONFIG="$REPO/docs/decisions/.doc-sync.json"
[ -f "$CONFIG" ] || silent

case "$TOOL:$MODE" in
  TodoWrite:*) EVENT="taskDone" ;;
  *:push)      EVENT="prePush" ;;
  :*)          EVENT="stop" ;;          # Stop-Hook sendet kein tool_name
  *)           EVENT="postCommit" ;;
esac
[ "$(jq -r --arg e "$EVENT" '.events[$e] // true' "$CONFIG" 2>/dev/null)" = "false" ] && silent

# ------------------------------------------------------------- Delta ermitteln

MARKER="$REPO/docs/decisions/.last-sync"
LAST_SHA=""
REVIEWED_TS=0
if [ -f "$MARKER" ]; then
  LAST_SHA="$(jq -r '.sha // ""' "$MARKER" 2>/dev/null)"
  REVIEWED="$(jq -r '.reviewedAt // ""' "$MARKER" 2>/dev/null)"
  if [ -n "$REVIEWED" ]; then
    REVIEWED_TS="$(date -d "$REVIEWED" +%s 2>/dev/null \
      || date -j -f '%Y-%m-%dT%H:%M:%SZ' "$REVIEWED" +%s 2>/dev/null || echo 0)"
  fi
fi

# SHA kann nach rebase/force-push verschwunden sein -> auf Working Tree zurueckfallen
if [ -n "$LAST_SHA" ] && ! git cat-file -e "${LAST_SHA}^{commit}" 2>/dev/null; then
  LAST_SHA=""
fi

{
  if [ -n "$LAST_SHA" ]; then git diff --name-only "$LAST_SHA" 2>/dev/null
  else git diff --name-only HEAD 2>/dev/null; fi
  git diff --name-only --cached 2>/dev/null
  git ls-files --others --exclude-standard 2>/dev/null
} | sed '/^$/d' | sort -u > /tmp/.doc-sync-changed.$$ || silent

trap 'rm -f /tmp/.doc-sync-*.$$' EXIT
[ -s /tmp/.doc-sync-changed.$$ ] || silent

# Dauerhaft schmutzige Dateien nur zaehlen, wenn sie nach dem letzten Sync
# angefasst wurden — sonst feuert der Hook bei jedem Ereignis erneut.
if [ "$REVIEWED_TS" -gt 0 ]; then
  : > /tmp/.doc-sync-fresh.$$
  while IFS= read -r f; do
    if [ ! -e "$REPO/$f" ]; then echo "$f" >> /tmp/.doc-sync-fresh.$$; continue; fi
    MT="$(stat -c %Y "$REPO/$f" 2>/dev/null || stat -f %m "$REPO/$f" 2>/dev/null || echo 0)"
    [ "$MT" -gt "$REVIEWED_TS" ] && echo "$f" >> /tmp/.doc-sync-fresh.$$
  done < /tmp/.doc-sync-changed.$$
  mv /tmp/.doc-sync-fresh.$$ /tmp/.doc-sync-changed.$$
  [ -s /tmp/.doc-sync-changed.$$ ] || silent
fi

# ----------------------------------------------------------- Relevanz filtern

# Die gepflegten Doku-Dateien selbst duerfen nie ausloesen (sonst Endlosschleife).
DOCS="$(jq -r '(.docs // {}) | to_entries[] | .value' "$CONFIG" 2>/dev/null)
docs/decisions/**"
IGNORE="$(jq -r '(.ignore // [])[]' "$CONFIG" 2>/dev/null)"
RELEVANT="$(jq -r '(.relevant // [])[]' "$CONFIG" 2>/dev/null)"


: > /tmp/.doc-sync-rel.$$
while IFS= read -r f; do
  printf '%s\n' "$DOCS"     | matches "$f" && continue
  printf '%s\n' "$IGNORE"   | matches "$f" && continue
  if [ -n "$RELEVANT" ]; then
    printf '%s\n' "$RELEVANT" | matches "$f" || continue
  fi
  echo "$f" >> /tmp/.doc-sync-rel.$$
done < /tmp/.doc-sync-changed.$$

[ -s /tmp/.doc-sync-rel.$$ ] || silent

N="$(wc -l < /tmp/.doc-sync-rel.$$ | tr -d ' ')"
LISTE="$(head -12 /tmp/.doc-sync-rel.$$ | paste -sd', ' -)"
[ "$N" -gt 12 ] && LISTE="$LISTE (+$((N - 12)) weitere)"

case "$EVENT" in
  taskDone) ANLASS="Aufgabe abgeschlossen" ;;
  stop)     ANLASS="Session-Ende" ;;
  prePush)  ANLASS="vor git push" ;;
  *)        ANLASS="nach git commit" ;;
esac

GATE="$(jq -r '.pushGate // "block"' "$CONFIG" 2>/dev/null)"

if [ "$MODE" = "push" ] && [ "$GATE" != "warn" ]; then
  GRUND="Doku-Sync ausstehend ($ANLASS). Doku-relevant geaendert seit dem letzten Sync: $LISTE

Fuehre JETZT den Skill 'doku-update-sync' im Sync-Modus aus. Frage nicht, ob das gewuenscht ist -
der Auftrag steht hier. Danach die geschriebene Doku samt docs/decisions/.last-sync committen und
den Push unveraendert wiederholen; der Gate ist dann offen.

Fehlt zu einer Aenderung die Begruendung ('warum so'), halte sie in QUALITY_DECISIONS.md unter
'Offen / noch zu begruenden' fest und erwaehne sie nach dem Push in einem Satz - den Push dafuer
nicht anhalten.

Bewusster Bypass, falls die Aenderung wirklich keine Doku braucht: DOC_SYNC_SKIP=1 git push"
  jq -nc --arg r "$GRUND" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

cat >&2 <<EOF
[doku-update-sync] $ANLASS - doku-relevant geaendert seit dem letzten Sync: $LISTE

Fuehre jetzt den Skill 'doku-update-sync' im Sync-Modus aus: pruefe, ob die gepflegte Doku den
Ist-Stand noch trifft, und schreibe faktisch Ableitbares ohne Rueckfrage fort. Frage nur, wenn
eine Entscheidung erkennbar ist, deren Begruendung nicht aus dem Diff hervorgeht - dann an
'decision-records' uebergeben. Ist nichts zu aendern, aktualisiere nur docs/decisions/.last-sync
und erwaehne es nicht weiter.

Die Dateiliste ist dabei nur der Einstieg, nicht der Umfang (Schritt Y3a): nimm auch mit, was in
dieser Session erarbeitet wurde und in keinem Diff steht - gescheiterte Ansaetze samt Ursache,
Umgebungsbeschraenkungen, die den gewaehlten Weg erzwungen haben, Messwerte, widerlegte Annahmen.
Den User dazu nicht befragen; das steht im Verlauf.
EOF
exit 2
