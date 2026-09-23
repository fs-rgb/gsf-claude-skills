#!/usr/bin/env pwsh
<#
    doc-sync-gate.ps1 — Teil des Skills "doku-update-sync".

    Prueft, ob es seit dem letzten Doku-Sync doku-relevante Aenderungen gibt.
    Gibt es keine, endet das Skript vollstaendig stumm mit Exit 0 — das ist der
    Normalfall und die Voraussetzung dafuer, dass die Hooks eingeschaltet bleiben.

    Modi:
      -Mode check   Nach git commit / TodoWrite-Abschluss / Session-Ende.
                    Exit 2 + stderr -> Claude bekommt den Text als Arbeitsauftrag.
      -Mode push    Vor git push. Blockiert den Push (PreToolUse deny), solange
                    relevantes Delta undokumentiert ist.
      -Mode edit    Nach Edit/Write/NotebookEdit. Braucht KEIN Git — prueft direkt
                    die gerade bearbeitete Datei gegen "relevant"/"ignore", ohne
                    git diff. Deshalb der einzige Modus, der auch in einem Ordner
                    ohne Versionskontrolle funktioniert (z. B. reine Word-/PDF-
                    Ablage). check/push/stop bleiben git-gebunden — ohne Git gibt
                    es also keinen Session-Ende-Backstop, nur den Sofort-Hinweis
                    direkt nach der Bearbeitung.

    Bypass fuer den Push-Gate: DOC_SYNC_SKIP im Kommando mitgeben, z. B.
      DOC_SYNC_SKIP=1 git push
    Der Bypass wird im Kommandotext erkannt, nicht in der Prozessumgebung.

    Konfiguration: docs/decisions/.doc-sync.json (vom Skill im Setup-Modus erzeugt).
    Ohne Config endet das Skript stumm — ein Repo ohne Setup wird nie behelligt.
#>
[CmdletBinding()]
param(
    [ValidateSet('check', 'push', 'edit')]
    [string]$Mode = 'check'
)

# WICHTIG: NICHT auf 'Stop' setzen. Windows PowerShell verpackt jede stderr-Zeile eines nativen
# Programms in einen ErrorRecord; git schreibt routinemaessig Warnungen dorthin ("LF will be
# replaced by CRLF ..."). Mit 'Stop' wird daraus ein abbrechender Fehler, den der trap unten
# verschluckt - der Hook endet dann stumm mit Exit 0 und feuert NIE, ohne dass es auffaellt.
# Genau dieses stille Scheitern soll der Hook verhindern. Fehlerbehandlung passiert stattdessen
# explizit: try/catch an den Stellen, die wirklich scheitern koennen, plus $LASTEXITCODE-Pruefung.
$ErrorActionPreference = 'Continue'

function Exit-Silent { exit 0 }

trap { Exit-Silent }

function Convert-GlobToRegex([string]$glob) {
    $re = [Regex]::Escape($glob)
    $re = $re -replace '\\\*\\\*/', '(?:.*/)?'   # **/  -> beliebige Tiefe, auch keine
    $re = $re -replace '\\\*\\\*', '.*'          # **   -> alles
    $re = $re -replace '\\\*', '[^/]*'           # *    -> alles ausser /
    $re = $re -replace '\\\?', '[^/]'
    return "^$re$"
}

function Test-Match([string]$pfad, $muster) {
    foreach ($m in $muster) {
        if (-not $m) { continue }
        $p = [string]$m
        if ($p.EndsWith('/')) { $p = $p + '**' }
        if ($pfad -match (Convert-GlobToRegex $p)) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------- Hook-Payload

$raw = ''
try { $raw = [Console]::In.ReadToEnd() } catch { $raw = '' }

$payload = $null
if ($raw -and $raw.Trim()) {
    try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null }
}

# Schleifenschutz: ein Stop-Hook, der Claude zum Weiterarbeiten zwingt, wuerde
# sonst beim naechsten Stop erneut feuern.
if ($payload -and $payload.PSObject.Properties.Name -contains 'stop_hook_active') {
    if ($payload.stop_hook_active) { Exit-Silent }
}

$toolName = ''
if ($payload -and $payload.PSObject.Properties.Name -contains 'tool_name') {
    $toolName = [string]$payload.tool_name
}

$cmd = ''
if ($payload -and $payload.tool_input -and
    $payload.tool_input.PSObject.Properties.Name -contains 'command') {
    $cmd = [string]$payload.tool_input.command
}

# ------------------------------------------------------------------ Edit-Modus
# Eigener, git-unabhaengiger Zweig: prueft nur die eine gerade bearbeitete Datei,
# kein git diff noetig. Deshalb VOR dem git-gebundenen Rest und mit eigenem Exit.
if ($Mode -eq 'edit') {
    if ($toolName -ne 'Edit' -and $toolName -ne 'Write' -and $toolName -ne 'NotebookEdit') { Exit-Silent }

    $filePath = ''
    if ($payload.tool_input -and $payload.tool_input.PSObject.Properties.Name -contains 'file_path') {
        $filePath = [string]$payload.tool_input.file_path
    }
    if (-not $filePath) { Exit-Silent }

    # Root: git bevorzugt (falls vorhanden), sonst das Arbeitsverzeichnis des Hooks -
    # das ist bei Claude Code immer der Projektordner, auch ohne Git.
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) { $root = (Get-Location).Path } else { $root = $root.Trim() }

    $configPath = Join-Path $root 'docs/decisions/.doc-sync.json'
    if (-not (Test-Path -LiteralPath $configPath)) { Exit-Silent }
    try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Exit-Silent }

    if ($config.events -and $config.events.PSObject.Properties.Name -contains 'onEdit') {
        if (-not $config.events.onEdit) { Exit-Silent }
    }

    $rel = $filePath.Replace('\', '/')
    try {
        $full = [System.IO.Path]::GetFullPath($filePath)
        $rootFull = [System.IO.Path]::GetFullPath($root)
        if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
            $rel = $full.Substring($rootFull.Length).TrimStart('\', '/').Replace('\', '/')
        }
    }
    catch {}

    $docPfade = @()
    if ($config.docs) { foreach ($p in $config.docs.PSObject.Properties) { $docPfade += [string]$p.Value } }
    $docPfade += 'docs/decisions/**'
    if (Test-Match $rel $docPfade) { Exit-Silent }
    if ($config.ignore -and (Test-Match $rel $config.ignore)) { Exit-Silent }
    if ($config.relevant -and $config.relevant.Count -gt 0) {
        if (-not (Test-Match $rel $config.relevant)) { Exit-Silent }
    }

    # Drosselung: pro Sync-Zyklus (reviewedAt aus .last-sync) nur einmal je Datei
    # nudgen - sonst meldet sich der Hook bei jeder einzelnen Bearbeitung erneut.
    $reviewedAt = ''
    $lastSyncPath = Join-Path $root 'docs/decisions/.last-sync'
    if (Test-Path -LiteralPath $lastSyncPath) {
        try { $reviewedAt = [string]((Get-Content -LiteralPath $lastSyncPath -Raw -Encoding UTF8 | ConvertFrom-Json).reviewedAt) }
        catch {}
    }
    $stateDir = Join-Path $root '.claude/hooks'
    $statePath = Join-Path $stateDir '.doc-sync-onedit.json'
    $state = @{}
    if (Test-Path -LiteralPath $statePath) {
        try {
            (Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties |
                ForEach-Object { $state[$_.Name] = [string]$_.Value }
        }
        catch {}
    }
    if ($state.ContainsKey($rel) -and $state[$rel] -eq $reviewedAt) { Exit-Silent }
    $state[$rel] = $reviewedAt
    try {
        if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
        ($state | ConvertTo-Json -Compress) | Set-Content -LiteralPath $statePath -Encoding UTF8
    }
    catch {}

    [Console]::Error.WriteLine(@"
[doku-update-sync] '$rel' bearbeitet - laut Konfiguration doku-relevant.

Kein Git-Hook noetig fuer diesen Hinweis: pruefe direkt jetzt, in derselben Aufgabe, ob die
zugehoerige Beschreibung (docs/decisions/.doc-sync.json -> "docs") noch stimmt, und schreibe
faktisch Ableitbares still fort. Ist nichts zu aendern, einfach weiterarbeiten - dieser Hinweis
erscheint fuer diese Datei erst nach dem naechsten echten Sync erneut.
"@)
    exit 2
}

# --- Nur bei den wirklich gemeinten Ereignissen anspringen --------------------

if ($toolName -eq 'Bash' -or $toolName -eq 'PowerShell') {
    if ($Mode -eq 'push') {
        if ($cmd -notmatch '(^|[;&|\(\s])git\s+push') { Exit-Silent }
        if ($cmd -match 'DOC_SYNC_SKIP') { Exit-Silent }   # bewusster, sichtbarer Bypass
    }
    else {
        if ($cmd -notmatch '(^|[;&|\(\s])git\s+commit') { Exit-Silent }
    }
}

# TodoWrite zaehlt erst als "Aufgabe fertig", wenn nichts mehr offen ist.
if ($toolName -eq 'TodoWrite') {
    if ($Mode -eq 'push') { Exit-Silent }
    $todos = $null
    if ($payload.tool_input -and
        $payload.tool_input.PSObject.Properties.Name -contains 'todos') {
        $todos = $payload.tool_input.todos
    }
    if (-not $todos) { Exit-Silent }
    $offen = @($todos | Where-Object { $_.status -ne 'completed' })
    if ($offen.Count -gt 0) { Exit-Silent }
}

# ------------------------------------------------------------------- Repo/Config

$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) { Exit-Silent }
$repoRoot = $repoRoot.Trim()

$configPath = Join-Path $repoRoot 'docs/decisions/.doc-sync.json'
if (-not (Test-Path -LiteralPath $configPath)) { Exit-Silent }

try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
catch { Exit-Silent }

# Einzelne Events abschaltbar, ohne den Hook aus settings.json zu entfernen.
$eventKey = switch ($true) {
    ($toolName -eq 'TodoWrite') { 'taskDone'; break }
    ($Mode -eq 'push')          { 'prePush';  break }
    ($toolName -eq '')          { 'stop';     break }   # Stop-Hook sendet kein tool_name
    default                     { 'postCommit' }
}
if ($config.events -and $config.events.PSObject.Properties.Name -contains $eventKey) {
    if (-not $config.events.$eventKey) { Exit-Silent }
}

# --------------------------------------------------------------- Delta ermitteln

$lastSyncPath = Join-Path $repoRoot 'docs/decisions/.last-sync'
$lastSha = ''
$reviewedAt = [DateTime]::MinValue
if (Test-Path -LiteralPath $lastSyncPath) {
    try {
        $marker = Get-Content -LiteralPath $lastSyncPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $lastSha = [string]$marker.sha
        if ($marker.reviewedAt) { $reviewedAt = [DateTime]::Parse($marker.reviewedAt).ToUniversalTime() }
    }
    catch { $lastSha = '' }
}

$changed = New-Object System.Collections.Generic.HashSet[string]

function Add-Files($lines) {
    foreach ($l in $lines) {
        if ($l -and $l.Trim()) { [void]$changed.Add($l.Trim().Replace('\', '/')) }
    }
}

if ($lastSha) {
    # Existiert der SHA nicht mehr (rebase, force-push, frischer Clone einer
    # umgeschriebenen Historie), faellt die Pruefung auf den Working-Tree zurueck.
    & git cat-file -e "$lastSha^{commit}" 2>$null
    if ($LASTEXITCODE -eq 0) { Add-Files (& git diff --name-only $lastSha 2>$null) }
    else { $lastSha = '' }
}
if (-not $lastSha) {
    Add-Files (& git diff --name-only HEAD 2>$null)
}
Add-Files (& git diff --name-only --cached 2>$null)
Add-Files (& git ls-files --others --exclude-standard 2>$null)

if ($changed.Count -eq 0) { Exit-Silent }

# Unverfolgte/ungestagte Dateien nur zaehlen, wenn sie nach dem letzten Sync
# angefasst wurden — sonst wuerde ein dauerhaft schmutziger Working Tree den
# Hook bei jedem Ereignis erneut ausloesen.
if ($reviewedAt -gt [DateTime]::MinValue) {
    $frisch = @()
    foreach ($f in $changed) {
        $voll = Join-Path $repoRoot $f
        if (-not (Test-Path -LiteralPath $voll)) { $frisch += $f; continue }   # geloescht = relevant
        try {
            if ((Get-Item -LiteralPath $voll).LastWriteTimeUtc -gt $reviewedAt) { $frisch += $f }
        }
        catch { $frisch += $f }
    }
    $changed = New-Object System.Collections.Generic.HashSet[string]
    Add-Files $frisch
    if ($changed.Count -eq 0) { Exit-Silent }
}

# ------------------------------------------------------------- Relevanz filtern

# Die gepflegten Doku-Dateien selbst duerfen nie ausloesen — sonst dreht sich
# der Sync im Kreis (Doku aendern -> Hook feuert -> Doku aendern -> ...).
$docPfade = @()
if ($config.docs) {
    foreach ($p in $config.docs.PSObject.Properties) { $docPfade += [string]$p.Value }
}
$docPfade += 'docs/decisions/**'

$relevant = @()
foreach ($f in $changed) {
    if (Test-Match $f $docPfade) { continue }
    if ($config.ignore -and (Test-Match $f $config.ignore)) { continue }
    if ($config.relevant -and $config.relevant.Count -gt 0) {
        if (-not (Test-Match $f $config.relevant)) { continue }
    }
    $relevant += $f
}

if ($relevant.Count -eq 0) { Exit-Silent }

# ------------------------------------------------------------------- Ausgeben

$liste = ($relevant | Sort-Object | Select-Object -First 12) -join ', '
if ($relevant.Count -gt 12) { $liste += " (+$($relevant.Count - 12) weitere)" }

$anlass = switch ($eventKey) {
    'taskDone'   { 'Aufgabe abgeschlossen' }
    'stop'       { 'Session-Ende' }
    'prePush'    { 'vor git push' }
    default      { 'nach git commit' }
}

if ($Mode -eq 'push' -and $config.pushGate -ne 'warn') {
    $grund = @"
Doku-Sync ausstehend ($anlass). Doku-relevant geaendert seit dem letzten Sync: $liste

Fuehre JETZT den Skill 'doku-update-sync' im Sync-Modus aus. Frage nicht, ob das gewuenscht ist -
der Auftrag steht hier. Danach die geschriebene Doku samt docs/decisions/.last-sync committen und
den Push unveraendert wiederholen; der Gate ist dann offen.

Fehlt zu einer Aenderung die Begruendung ('warum so'), halte sie in QUALITY_DECISIONS.md unter
'Offen / noch zu begruenden' fest und erwaehne sie nach dem Push in einem Satz - den Push dafuer
nicht anhalten.

Bewusster Bypass, falls die Aenderung wirklich keine Doku braucht: DOC_SYNC_SKIP=1 git push
"@
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $grund
        }
    }
    $out | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

# check-Modus (und push-Gate im Warn-Betrieb): Exit 2 schickt stderr an Claude.
[Console]::Error.WriteLine(@"
[doku-update-sync] $anlass - doku-relevant geaendert seit dem letzten Sync: $liste

Fuehre jetzt den Skill 'doku-update-sync' im Sync-Modus aus: pruefe, ob die gepflegte Doku den
Ist-Stand noch trifft, und schreibe faktisch Ableitbares ohne Rueckfrage fort. Frage nur, wenn
eine Entscheidung erkennbar ist, deren Begruendung nicht aus dem Diff hervorgeht - dann an
'decision-records' uebergeben. Ist nichts zu aendern, aktualisiere nur docs/decisions/.last-sync
und erwaehne es nicht weiter.

Die Dateiliste ist dabei nur der Einstieg, nicht der Umfang (Schritt Y3a): nimm auch mit, was in
dieser Session erarbeitet wurde und in keinem Diff steht - gescheiterte Ansaetze samt Ursache,
Umgebungsbeschraenkungen, die den gewaehlten Weg erzwungen haben, Messwerte, widerlegte Annahmen.
Den User dazu nicht befragen; das steht im Verlauf.
"@)
exit 2
