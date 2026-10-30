#!/bin/bash
# End-to-end acceptance of the installed app. Uses existing Accessibility and screen
# recording grants only; never requests permissions or sends Apple Events.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=/tmp/lighttts-screen.lock
TMP=""; locked=0; clipboard=0; say_pid=""; text_open=0; note_open=0; chrome_open=0
superwhisper=""
cleanup() {
  local status=$?
  trap - EXIT
  [ -z "$say_pid" ] || kill "$say_pid" 2>/dev/null || true
  if [ -n "$TMP" ] && [ -x "$TMP/driver" ]; then
    if [ "$text_open" = 1 ]; then open -a TextEdit; sleep 1; "$D" key 1 1048576; sleep 1; "$D" key 13 1048576; fi
    if [ "$note_open" = 1 ]; then open -a Notes; sleep 1; note_cleanup || { echo 'FAIL: Notes cleanup' >&2; status=1; }; fi
    if [ "$chrome_open" = 1 ]; then open -a 'Google Chrome'; sleep 1; "$D" key 13 1048576; fi
    [ "$clipboard" = 0 ] || "$D" restore "$TMP/clipboard" || { echo 'FAIL: clipboard restore' >&2; status=1; }
  fi
  [ -z "$superwhisper" ] || open "$superwhisper" || { echo 'FAIL: SuperWhisper relaunch' >&2; status=1; }
  [ -z "$TMP" ] || rm -rf "$TMP"
  [ "$locked" = 0 ] || rmdir "$LOCK" 2>/dev/null || { echo 'FAIL: could not release screen lock' >&2; status=1; }
  exit "$status"
}
note_cleanup() { "$D" key 0 1048576; "$D" key 51 0; sleep 1; "$D" notes-back || return 1; sleep 1; }
trap cleanup EXIT
trap 'exit 130' INT TERM
for ((i=0; i<1800; i++)); do if mkdir "$LOCK" 2>/dev/null; then locked=1; break; fi; sleep 1; done
if [ "$locked" = 0 ]; then printf '%-32s %-6s %s\n' CHECK RESULT DETAIL 'Screen lock' FAIL 'busy for 30 minutes'; exit 1; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-acceptance.XXXXXX") || exit 1
swiftc "$ROOT/scripts/acceptance/driver.swift" -o "$TMP/driver" || exit 1
D="$TMP/driver"
"$D" permissions || { echo 'FAIL: screen recording or microphone permission not granted; no prompt requested' >&2; exit 1; }
"$D" trust || { echo 'FAIL: Accessibility not granted; no prompt requested' >&2; exit 1; }
"$D" save "$TMP/clipboard" || exit 1; clipboard=1
superwhisper=$("$D" superwhisper-path) || exit 1
"$D" quit-superwhisper || exit 1
mkdir -p /tmp/lt-shots
rm -f /tmp/lt-shots/accept-{textedit-1,textedit-2,textedit-3,notes,chrome,finder,esc}.png
failures=0; rows="$TMP/rows"; : > "$rows"
result() { printf '%-32s %-6s %s\n' "$1" "$2" "$3" | tee -a "$rows"; [ "$2" = PASS ] || failures=$((failures+1)); }
window_count() { "$D" windows 2>>"$TMP/windows"; }
idle() { sleep 2; local n; n=$(window_count) || n=-1; [ "$n" = 0 ]; }
shortcut() { if [ "$right" = 1 ]; then "$D" right-option; else "$D" key "$code" "$mods"; fi; }
read_pref() { defaults read com.lighttts.app "$1" 2>/dev/null || printf '%s' "$2"; }
code=$(read_pref hotkeyCode 49); mods=$(read_pref hotkeyModifiers 524288); right=$(read_pref rightOption 0)
printf '%-32s %-6s %s\n' CHECK RESULT DETAIL
[ -d "$HOME/Applications/LightTTS.app" ] && pgrep -x LightTTS >/dev/null && result 'Installed app running' PASS "$HOME/Applications/LightTTS.app" || result 'Installed app running' FAIL 'Launch the installed app first'
result 'Accessibility' PASS 'already granted'
if idle; then result 'Popup idle before' PASS 'no LightTTS windows'; else result 'Popup idle before' FAIL 'LightTTS window visible or enumeration failed'; fi
record() {
  popup=0; shortcut; sleep 1
  [ "$(window_count)" -gt 0 ] 2>/dev/null && popup=1
  say -r 140 'The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.' & say_pid=$!
  sleep 3
  stop_ms=$(python3 -c 'import time; print(int(time.monotonic()*1000))')
  shortcut
  kill "$say_pid" 2>/dev/null || true; wait "$say_pid" 2>/dev/null || true; say_pid=""
}
contains_speech() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -Eq 'quick|brown|fox|lazy|dog'; }
copy_field() { "$D" set 'LIGHTTTS_ACCEPTANCE_EMPTY'; "$D" key 0 1048576; "$D" key 8 1048576; sleep 0.2; "$D" get; }
wait_field() {
  found=0; elapsed='no transcript in 30s'
  for ((j=0; j<60; j++)); do
    content=$(copy_field)
    if contains_speech "$content"; then now=$(python3 -c 'import time; print(int(time.monotonic()*1000))'); elapsed="$((now-stop_ms)) ms"; found=1; break; fi
    sleep 0.5
  done
}
shot() { screencapture -x "/tmp/lt-shots/accept-$1.png" || result "$1 screenshot" FAIL 'screencapture failed'; }
finish_popup() { if [ "$popup" = 1 ] && idle; then result "$1 popup lifecycle" PASS 'visible recording; absent 2s after'; else result "$1 popup lifecycle" FAIL 'missing during recording or visible 2s after'; fi; }
text_start() {
  : > "$TMP/test.txt"
  open -a TextEdit "$TMP/test.txt" || return 1
  text_open=1; sleep 2; "$D" focus com.apple.TextEdit
}
text_close() { "$D" key 1 1048576; sleep 1; "$D" key 13 1048576; sleep 1; text_open=0; }
for n in 1 2 3; do
  if text_start; then
    record; wait_field; shot "textedit-$n"
    if [ "$found" = 1 ]; then result "TextEdit toggle $n" PASS "stop to text $elapsed"; else result "TextEdit toggle $n" FAIL "$elapsed"; fi
    finish_popup "TextEdit $n"; text_close
  else result "TextEdit toggle $n" FAIL 'document or focus unavailable'; result "TextEdit $n popup lifecycle" FAIL 'run unavailable'; fi
done
if open -a Notes; then
  sleep 2; "$D" key 45 1048576; note_open=1; sleep 2
  if "$D" focus com.apple.Notes; then
    record; wait_field; shot notes
    if [ "$found" = 1 ]; then result 'Notes paste' PASS "speech in new note ($elapsed)"; else result 'Notes paste' FAIL "$elapsed"; fi
    finish_popup Notes
  else result 'Notes paste' FAIL 'focus unavailable'; result 'Notes popup lifecycle' FAIL 'run unavailable'; fi
  if note_cleanup; then note_open=0; else result 'Notes cleanup' FAIL 'could not leave test note'; fi
else result 'Notes paste' FAIL 'Notes unavailable'; result 'Notes popup lifecycle' FAIL 'run unavailable'; fi
if open -a 'Google Chrome' 'data:text/html,<textarea%20autofocus%20rows=10%20cols=60></textarea>'; then
  chrome_open=1; sleep 3
  if "$D" focus com.google.Chrome; then
    record; wait_field; shot chrome
    if [ "$found" = 1 ]; then result 'Chrome paste' PASS "speech in data URL field ($elapsed)"; else result 'Chrome paste' FAIL "$elapsed"; fi
    finish_popup Chrome
  else result 'Chrome paste' FAIL 'focus unavailable'; result 'Chrome popup lifecycle' FAIL 'run unavailable'; fi
  "$D" key 13 1048576; chrome_open=0
else result 'Chrome paste' FAIL 'Chrome unavailable'; result 'Chrome popup lifecycle' FAIL 'run unavailable'; fi
if open -a Finder; then
  sleep 1; "$D" key 4 1572864; sleep 1
  if "$D" desktop; then
    "$D" set 'LIGHTTTS_ACCEPTANCE_EMPTY'; record; found=0
    for ((j=0; j<60; j++)); do content=$("$D" get); if contains_speech "$content"; then found=1; break; fi; sleep 0.5; done
    # The transcript can arrive before the recording panel has finished dismissing.
    # Check for an error only after the same settling period as the lifecycle check.
    finish_popup Finder
    shot finder
    if [ "$found" = 1 ] && [ "$(window_count)" = 0 ]; then result 'Finder clipboard fallback' PASS 'speech on clipboard; no error window'; else result 'Finder clipboard fallback' FAIL "transcript found=$found; LightTTS windows=$(window_count)"; fi
  else result 'Finder clipboard fallback' FAIL 'no uncovered desktop point'; result 'Finder popup lifecycle' FAIL 'run unavailable'; fi
else result 'Finder clipboard fallback' FAIL 'Finder unavailable'; result 'Finder popup lifecycle' FAIL 'run unavailable'; fi
if text_start; then
  shortcut; sleep 1; popup=$(window_count); "$D" key 53 0; sleep 1; content=$(copy_field); shot esc
  if [ "$popup" -gt 0 ] 2>/dev/null && [ "$(window_count)" = 0 ] && [ "$content" = 'LIGHTTTS_ACCEPTANCE_EMPTY' ]; then result 'Esc cancel' PASS 'empty document; popup gone within 1s'; else result 'Esc cancel' FAIL 'popup or document state unexpected'; fi
  text_close
  if idle; then result 'Esc popup idle' PASS 'no window 2s after'; else result 'Esc popup idle' FAIL 'window visible'; fi
else result 'Esc cancel' FAIL 'TextEdit unavailable'; result 'Esc popup idle' FAIL 'run unavailable'; fi
if top -l 3 -s 5 -stats pid,command,cpu,power,idlew > "$TMP/top" 2>>"$TMP/errors"; then
  awk '$2 == "LightTTS" || $2 == "LightTTSEngine" {print}' "$TMP/top"
  if awk '/^PID / {sample++} sample >= 2 && ($2 == "LightTTS" || $2 == "LightTTSEngine") {seen=1; if ($2 == "LightTTS") app=1; if (($3+0)>1) bad=1} END {exit !(seen && app && !bad)}' "$TMP/top"; then result 'Idle CPU' PASS 'last two top samples <= 1%'; else result 'Idle CPU' FAIL 'missing app or CPU above 1%; see top rows'; fi
else result 'Idle CPU' FAIL 'top failed'; fi
printf '\nAcceptance results\n%-32s %-6s %s\n' CHECK RESULT DETAIL
cat "$rows"
[ ! -s "$TMP/errors" ] || { printf '\nDiagnostics:\n'; cat "$TMP/errors"; }
[ "$failures" = 0 ]
