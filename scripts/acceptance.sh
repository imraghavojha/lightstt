#!/bin/bash
# End-to-end acceptance of the already installed app. Requires existing Accessibility,
# Screen Recording and Automation grants; never requests or changes permissions.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=/tmp/lighttts-screen.lock
TMP=""; locked=0; clipboard=0; text_created=0; note_id=""; chrome_id=""; say_pid=""
text_was_running=0; notes_was_running=0; allow_TextEdit=0; allow_Notes=0; allow_Chrome=0; allow_Finder=0
cleanup() {
  local status=$?
  trap - EXIT
  [ -z "$say_pid" ] || kill "$say_pid" 2>/dev/null || true
  if [ -n "$TMP" ] && [ -x "$TMP/driver" ]; then
    [ "$text_created" = 0 ] || "$TMP/driver" script 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1 || true
    [ -z "$note_id" ] || "$TMP/driver" script "tell application \"Notes\" to delete (first note whose id is \"$note_id\")" >/dev/null 2>&1 || true
    [ -z "$chrome_id" ] || "$TMP/driver" script "tell application \"Google Chrome\" to close (first window whose id is $chrome_id)" >/dev/null 2>&1 || true
    [ "$text_was_running" = 1 ] || [ "$allow_TextEdit" = 0 ] || "$TMP/driver" script 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1 || true
    [ "$notes_was_running" = 1 ] || [ "$allow_Notes" = 0 ] || "$TMP/driver" script 'tell application "Notes" to quit' >/dev/null 2>&1 || true
    [ "$clipboard" = 0 ] || "$TMP/driver" restore "$TMP/clipboard" || { echo 'FAIL: clipboard restore' >&2; status=1; }
  fi
  [ -z "$TMP" ] || rm -rf "$TMP"
  [ "$locked" = 0 ] || rmdir "$LOCK" 2>/dev/null || { echo "FAIL: could not release screen lock" >&2; status=1; }
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
for ((i=0; i<30; i++)); do if mkdir "$LOCK" 2>/dev/null; then locked=1; break; fi; sleep 1; done
if [ "$locked" = 0 ]; then printf '%-32s %-6s %s\n' CHECK RESULT DETAIL 'Screen lock' FAIL 'busy for 30 seconds'; exit 1; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-acceptance.XXXXXX") || exit 1
swiftc "$ROOT/scripts/acceptance/driver.swift" -o "$TMP/driver" || exit 1
D="$TMP/driver"
"$D" save "$TMP/clipboard" || exit 1; clipboard=1
pgrep -x TextEdit >/dev/null && text_was_running=1
pgrep -x Notes >/dev/null && notes_was_running=1
failures=0; rows="$TMP/rows"; : > "$rows"
result() { printf '%-32s %-6s %s\n' "$1" "$2" "$3" | tee -a "$rows"; [ "$2" = PASS ] || failures=$((failures+1)); }
script() { "$D" script "$1" 2>>"$TMP/errors"; }
window_count() { "$D" windows 2>>"$TMP/windows"; }
idle() { sleep 2; local n; n=$(window_count) || n=-1; [ "$n" = 0 ]; }
shortcut() { if [ "$right" = 1 ]; then "$D" right-option; else "$D" key "$code" "$mods"; fi; }
read_pref() { defaults read com.lighttts.app "$1" 2>/dev/null || printf '%s' "$2"; }
code=$(read_pref hotkeyCode 49); mods=$(read_pref hotkeyModifiers 524288); right=$(read_pref rightOption 0)
printf '%-32s %-6s %s\n' CHECK RESULT DETAIL
[ -d "$HOME/Applications/LightTTS.app" ] && pgrep -x LightTTS >/dev/null && result 'Installed app running' PASS "$HOME/Applications/LightTTS.app" || result 'Installed app running' FAIL 'Launch the installed app first'
if "$D" trust; then result 'Accessibility' PASS 'already granted'; else result 'Accessibility' FAIL 'not granted; no prompt requested'; fi
for pair in 'com.apple.TextEdit:TextEdit' 'com.apple.Notes:Notes' 'com.google.Chrome:Chrome' 'com.apple.finder:Finder'; do
  bundle=${pair%%:*}; name=${pair#*:}; if "$D" automation "$bundle"; then eval "allow_$name=1"; else eval "allow_$name=0"; fi
done
if idle; then result 'Popup idle before' PASS 'no LightTTS windows'; else result 'Popup idle before' FAIL 'LightTTS window visible or enumeration failed'; fi
# Each recording is started and released, then speech plays with no key held for 3 s.
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
finish_popup() { if [ "$popup" = 1 ] && idle; then result "$1 popup lifecycle" PASS 'visible recording; absent 2s after'; else result "$1 popup lifecycle" FAIL 'missing during recording or visible 2s after'; fi; }
for n in 1 2 3; do
  if [ "$allow_TextEdit" = 1 ] && script $'tell application "TextEdit" to activate\ntell application "TextEdit" to make new document' >/dev/null; then
    text_created=1; sleep 1; record; found=0; elapsed='no transcript in 30s'
    for ((j=0; j<60; j++)); do
      content=$(script 'tell application "TextEdit" to get text of front document' || true)
      if contains_speech "$content"; then now=$(python3 -c 'import time; print(int(time.monotonic()*1000))'); elapsed="$((now-stop_ms)) ms"; found=1; break; fi; sleep 0.5
    done
    if [ "$found" = 1 ]; then result "TextEdit toggle $n" PASS "stop to text $elapsed"; else result "TextEdit toggle $n" FAIL "$elapsed"; fi
    finish_popup "TextEdit $n"
    script 'tell application "TextEdit" to close front document saving no' >/dev/null && text_created=0
  else result "TextEdit toggle $n" FAIL 'Automation unavailable or document creation failed'; result "TextEdit $n popup lifecycle" FAIL 'run unavailable'; fi
done
if [ "$allow_Notes" = 1 ]; then
  note_id=$(script $'tell application "Notes"\nactivate\nset n to make new note at default account with properties {body:"LightTTS acceptance"}\nshow n\nreturn id of n\nend tell' || true)
fi
if [ -n "$note_id" ]; then
  sleep 2; "$D" key 36 0; record; sleep 5; content=$(copy_field)
  if contains_speech "$content"; then result 'Notes paste' PASS 'speech in new note'; else result 'Notes paste' FAIL 'speech not found in note'; fi
  finish_popup Notes
  if script "tell application \"Notes\" to delete (first note whose id is \"$note_id\")" >/dev/null; then note_id=""; else result 'Notes cleanup' FAIL 'could not delete test note'; fi
else result 'Notes paste' FAIL 'Automation unavailable or note creation failed'; result 'Notes popup lifecycle' FAIL 'run unavailable'; fi
if [ "$allow_Chrome" = 1 ]; then
  chrome_id=$(script $'tell application "Google Chrome"\nactivate\nset w to make new window\nset URL of active tab of w to "data:text/html,<textarea%20autofocus%20rows=10%20cols=60></textarea>"\nreturn id of w\nend tell' || true)
fi
if [[ "$chrome_id" =~ ^[0-9]+$ ]]; then
  sleep 2; record; sleep 5; content=$(copy_field)
  if contains_speech "$content"; then result 'Chrome paste' PASS 'speech in data URL field'; else result 'Chrome paste' FAIL 'speech not found in field'; fi
  finish_popup Chrome
  if script "tell application \"Google Chrome\" to close (first window whose id is $chrome_id)" >/dev/null; then chrome_id=""; else result 'Chrome cleanup' FAIL 'could not close test window'; fi
else chrome_id=""; result 'Chrome paste' FAIL 'Automation unavailable or window creation failed'; result 'Chrome popup lifecycle' FAIL 'run unavailable'; fi
if [ "$allow_Finder" = 1 ] && script 'tell application "Finder" to activate' >/dev/null && "$D" desktop 2>>"$TMP/errors"; then
  sleep 1; "$D" set 'LIGHTTTS_ACCEPTANCE_EMPTY'; record; sleep 5; content=$("$D" get)
  if contains_speech "$content" && [ "$(window_count)" = 0 ]; then result 'Finder clipboard fallback' PASS 'speech on clipboard; no error window'; else result 'Finder clipboard fallback' FAIL 'no speech on clipboard or LightTTS window visible'; fi
  finish_popup Finder
else result 'Finder clipboard fallback' FAIL 'Finder Automation unavailable'; result 'Finder popup lifecycle' FAIL 'run unavailable'; fi
if [ "$allow_TextEdit" = 1 ] && script $'tell application "TextEdit" to activate\ntell application "TextEdit" to make new document' >/dev/null; then
  text_created=1; sleep 1; shortcut; sleep 1; popup=$(window_count); "$D" key 53 0; sleep 1
  content=$(script 'tell application "TextEdit" to get text of front document' || true)
  if [ "$popup" -gt 0 ] 2>/dev/null && [ "$(window_count)" = 0 ] && [ -z "$content" ]; then result 'Esc cancel' PASS 'empty document; popup gone within 1s'; else result 'Esc cancel' FAIL 'popup or document state unexpected'; fi
  script 'tell application "TextEdit" to close front document saving no' >/dev/null && text_created=0
  if idle; then result 'Esc popup idle' PASS 'no window 2s after'; else result 'Esc popup idle' FAIL 'window visible'; fi
else result 'Esc cancel' FAIL 'TextEdit unavailable'; result 'Esc popup idle' FAIL 'run unavailable'; fi
if idle; then :; fi
if top -l 3 -s 5 -stats pid,command,cpu,power,idlew > "$TMP/top" 2>>"$TMP/errors"; then
  awk '$2 == "LightTTS" || $2 == "LightTTSEngine" {print}' "$TMP/top" > "$TMP/top-apps"
  cat "$TMP/top-apps"
  # Ignore first cumulative sample. Require the app and all sampled matching processes
  # in later samples to be at or below 1% CPU (approximately idle).
  if awk '/^PID / {sample++} sample >= 2 && ($2 == "LightTTS" || $2 == "LightTTSEngine") {seen=1; if ($2 == "LightTTS") app=1; if (($3+0)>1) bad=1} END {exit !(seen && app && !bad)}' "$TMP/top"; then result 'Idle CPU' PASS 'last two top samples <= 1%'; else result 'Idle CPU' FAIL 'missing app or CPU above 1%; see top rows'; fi
else result 'Idle CPU' FAIL 'top failed'; fi
printf '\nAcceptance results\n%-32s %-6s %s\n' CHECK RESULT DETAIL
cat "$rows"
[ ! -s "$TMP/errors" ] || { printf '\nAutomation diagnostics:\n'; cat "$TMP/errors"; }
[ "$failures" = 0 ]
