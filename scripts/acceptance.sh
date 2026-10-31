#!/bin/bash
# End-to-end acceptance of the installed app. Uses existing Accessibility and screen
# recording grants only; never requests permissions or sends Apple Events.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=/tmp/lighttts-screen.lock
TMP=""; locked=0; clipboard=0; say_pid=""; superwhisper=""; targets=""
cleanup() {
  local status=$? bundle identity file
  trap - EXIT INT TERM
  [ -z "$say_pid" ] || kill "$say_pid" 2>/dev/null || true
  if [ -n "$targets" ] && [ -f "$targets" ] && [ -x "$D" ]; then
    while IFS='|' read -r bundle identity file; do
      [ -z "$file" ] || rm -f -- "$file"
      "$D" close "$bundle" "$identity" || { echo "FAIL: cleanup $identity" >&2; status=1; }
    done < "$targets"
  fi
  if [ "$clipboard" = 1 ]; then "$D" restore "$TMP/clipboard" || { echo 'FAIL: clipboard restore' >&2; status=1; }; fi
  if [ -n "$superwhisper" ]; then open "$superwhisper"; else open -a superwhisper; fi || { echo 'FAIL: SuperWhisper relaunch' >&2; status=1; }
  [ -z "$TMP" ] || rm -rf "$TMP"
  [ "$locked" = 0 ] || rmdir "$LOCK" 2>/dev/null || { echo 'FAIL: could not release screen lock' >&2; status=1; }
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
for ((i=0; i<1800; i++)); do if mkdir "$LOCK" 2>/dev/null; then locked=1; break; fi; sleep 1; done
if [ "$locked" = 0 ]; then printf '%-32s %-6s %s\n' CHECK RESULT DETAIL 'Screen lock' FAIL 'busy for 30 minutes'; exit 1; fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-acceptance.XXXXXX") || exit 1
swiftc "$ROOT/scripts/acceptance/driver.swift" -o "$TMP/driver" || exit 1
D="$TMP/driver"
targets="$TMP/targets"; : > "$targets"
"$D" permissions || { echo 'FAIL: screen recording or microphone permission not granted; no prompt requested' >&2; exit 1; }
"$D" trust || { echo 'FAIL: Accessibility not granted; no prompt requested' >&2; exit 1; }
"$D" save "$TMP/clipboard" || exit 1; clipboard=1
running_superwhisper=$("$D" superwhisper-path) || exit 1
[ -z "$running_superwhisper" ] || superwhisper="$running_superwhisper"
"$D" quit-superwhisper || exit 1
mkdir -p /tmp/lt-shots

failures=0; rows="$TMP/rows"; : > "$rows"
result() { printf '%-32s %-6s %s\n' "$1" "$2" "$3" | tee -a "$rows"; [ "$2" != FAIL ] || failures=$((failures+1)); }
window_count() { "$D" windows 2>>"$TMP/windows"; }
idle() { sleep 2; local n; n=$(window_count) || n=-1; [ "$n" = 0 ]; }
focus() { "$D" focus "$target" "$identity"; }
shortcut() { if [ "$right" = 1 ]; then "$D" target-option "$target" "$identity"; else "$D" target-key "$target" "$identity" "$code" "$mods"; fi; }
read_pref() { defaults read com.lighttts.app "$1" 2>/dev/null || printf '%s' "$2"; }
code=$(read_pref hotkeyCode 49); mods=$(read_pref hotkeyModifiers 524288); right=$(read_pref rightOption 0)
printf '%-32s %-6s %s\n' CHECK RESULT DETAIL
[ -d "$HOME/Applications/LightTTS.app" ] && pgrep -x LightTTS >/dev/null && result 'Installed app running' PASS "$HOME/Applications/LightTTS.app" || result 'Installed app running' FAIL 'Launch the installed app first'
result 'Accessibility' PASS 'already granted'
if idle; then result 'Popup idle before' PASS 'no LightTTS windows'; else result 'Popup idle before' FAIL 'LightTTS window visible or enumeration failed'; fi
record() {
  popup=0; shortcut || return 1; sleep 1
  [ "$(window_count)" -gt 0 ] 2>/dev/null && popup=1
  say -r 140 'The quick brown fox jumps over the lazy dog. The quick brown fox jumps over the lazy dog.' & say_pid=$!
  sleep 3
  stop_ms=$(python3 -c 'import time; print(int(time.monotonic()*1000))')
  shortcut || { kill "$say_pid" 2>/dev/null || true; wait "$say_pid" 2>/dev/null || true; say_pid=""; return 1; }
  kill "$say_pid" 2>/dev/null || true; wait "$say_pid" 2>/dev/null || true; say_pid=""
}
contains_speech() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | grep -Eq 'quick|brown|fox|lazy|dog'; }
read_field() { "$D" read "$target" "$identity"; }
wait_field() {
  found=0; elapsed='no transcript in 30s'
  for ((j=0; j<60; j++)); do
    content=$(read_field) || { elapsed="focus or AXValue unavailable for $identity"; return 1; }
    if contains_speech "$content"; then now=$(python3 -c 'import time; print(int(time.monotonic()*1000))'); elapsed="$((now-stop_ms)) ms"; found=1; break; fi
    sleep 0.5
  done
}
shot() { screencapture -x "/tmp/lt-shots/accept5-$1.png" || echo "FAIL: screenshot $1" >&2; }
finish_popup() { if [ "$popup" = 1 ] && idle; then result "$1 popup lifecycle" PASS 'visible recording; absent 2s after'; else shot "$2-popup"; result "$1 popup lifecycle" FAIL 'missing during recording or visible 2s after'; fi; }
start_target() {
  target="$1"; identity="lt-accept-$(uuidgen)"; file=""
  if [ "$target" = com.apple.TextEdit ]; then
    file="/tmp/$identity.txt"; (set -C; : > "$file") || return 1
    printf '%s|%s|%s\n' "$target" "$identity" "$file" >> "$targets"
    open -a TextEdit "$file" || return 1
  else
    printf '%s|%s|%s\n' "$target" "$identity" "$file" >> "$targets"
    open -a 'Google Chrome' --args --new-window "data:text/html,<title>$identity</title><input autofocus id=t>" || return 1
  fi
  sleep 3
  if ! focus; then
    # Launch Services can ignore --args when Chrome is already running.
    if [ "$target" = com.google.Chrome ]; then
      local chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
      [ -x "$chrome" ] || return 1
      "$chrome" --new-window "data:text/html,<title>$identity</title><input autofocus id=t>" >/dev/null 2>&1 &
      sleep 3; focus
    else return 1; fi
  fi
}
close_target() {
  [ -z "$file" ] || rm -f -- "$file"
  if "$D" close "$target" "$identity"; then
    awk -F'|' -v id="$identity" '$2 != id' "$targets" > "$targets.new" && mv "$targets.new" "$targets"
  else result 'Target cleanup' FAIL "$identity"; fi
}
for n in 1 2 3; do
  if start_target com.apple.TextEdit; then
    if record; then wait_field || true; else found=0; elapsed='focus verification failed'; fi
    if [ "$found" = 1 ]; then result "TextEdit toggle $n" PASS "stop to text $elapsed"; else shot "textedit-$n"; result "TextEdit toggle $n" FAIL "$elapsed"; fi
    finish_popup "TextEdit $n" "textedit-$n"; close_target
  else shot "textedit-$n"; result "TextEdit toggle $n" FAIL 'document or focus unavailable'; result "TextEdit $n popup lifecycle" FAIL 'run unavailable'; fi
done
result 'Notes paste' SKIP 'new note window cannot be uniquely identified without Automation'
result 'Notes popup lifecycle' SKIP 'Notes target unavailable'
if start_target com.google.Chrome; then
  if record; then wait_field || true; else found=0; elapsed='focus verification failed'; fi
  if [ "$found" = 1 ]; then result 'Chrome paste' PASS "speech in data URL field ($elapsed)"; else shot chrome; result 'Chrome paste' FAIL "$elapsed"; fi
  finish_popup Chrome chrome; close_target
else shot chrome; result 'Chrome paste' FAIL 'window or focus unavailable'; result 'Chrome popup lifecycle' FAIL 'run unavailable'; fi
result 'Finder clipboard fallback' SKIP 'desktop has no uniquely identifiable test window'
result 'Finder popup lifecycle' SKIP 'Finder target unavailable'
if start_target com.apple.TextEdit; then
  if shortcut; then sleep 1; popup=$(window_count); "$D" target-key "$target" "$identity" 53 0 || true; sleep 1; content=$(read_field) || content=FOCUS_FAILED; else popup=0; content=FOCUS_FAILED; fi
  if [ "$popup" -gt 0 ] 2>/dev/null && [ "$(window_count)" = 0 ] && [ -z "$content" ]; then result 'Esc cancel' PASS 'empty document; popup gone within 1s'; else shot esc; result 'Esc cancel' FAIL 'popup, focus, or document state unexpected'; fi
  close_target
  if idle; then result 'Esc popup idle' PASS 'no window 2s after'; else shot esc-idle; result 'Esc popup idle' FAIL 'window visible'; fi
else shot esc; result 'Esc cancel' FAIL 'TextEdit unavailable'; result 'Esc popup idle' FAIL 'run unavailable'; fi
if top -l 3 -s 5 -stats pid,command,cpu,power,idlew > "$TMP/top" 2>>"$TMP/errors"; then
  awk '$2 == "LightTTS" || $2 == "LightTTSEngine" {print}' "$TMP/top"
  if awk '/^PID / {sample++} sample >= 2 && ($2 == "LightTTS" || $2 == "LightTTSEngine") {seen=1; if ($2 == "LightTTS") app=1; if (($3+0)>1) bad=1} END {exit !(seen && app && !bad)}' "$TMP/top"; then result 'Idle CPU' PASS 'last two top samples <= 1%'; else result 'Idle CPU' FAIL 'missing app or CPU above 1%; see top rows'; fi
else result 'Idle CPU' FAIL 'top failed'; fi
printf '\nAcceptance results\n%-32s %-6s %s\n' CHECK RESULT DETAIL
cat "$rows"
[ ! -s "$TMP/errors" ] || { printf '\nDiagnostics:\n'; cat "$TMP/errors"; }
[ "$failures" = 0 ]
