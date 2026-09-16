#!/usr/bin/env bash
# doc-sync-gate.sh — Teil des Skills "doku-update-sync".
# POSIX-/macOS-/Linux-Variante von doc-sync-gate.ps1. Siehe dort fuer die Doku.
#
#   ./doc-sync-gate.sh check   nach git commit / TodoWrite-Abschluss / Session-Ende
#   ./doc-sync-gate.sh push    vor git push (blockiert)
#
# Benoetigt jq. Bypass fuer den Push-Gate: DOC_SYNC_SKIP=1 git push

set -uo pipefail

MODE="${1:-check}"
silent() { exit 0; }

command -v jq >/dev/null 2>&1 || {
  echo "[doku-update-sync] Hook uebersprungen: jq nicht installiert (brew/apt install jq)." >&2
  exit 0
}

PAYLOAD="$(cat 2>/dev/null || true)"
jqp() { [ -n "$PAYLOAD" ] && printf '%s' "$PAYLOAD" | jq -r "$1" 2>/dev/null || true; }

# Schleifenschutz fuer den Stop-Hook
[ "$(jqp '.stop_hook_active // false')" = "true" ] && silent

TOOL="$(jqp '.tool_name // ""')"
CMD="$(jqp '.tool_input.command // ""')"

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
EOF
exit 2
