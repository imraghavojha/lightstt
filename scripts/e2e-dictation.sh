#!/bin/bash
# Requires existing microphone, Accessibility, Input Monitoring, and TextEdit automation grants.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-e2e.XXXXXX")
created=0
clipboard_saved=0
launched=0
was_running=0
pgrep -x TextEdit >/dev/null && was_running=1
cleanup() {
    status=$?
    if ((status)); then echo "FAIL: e2e exited with status $status" >&2; fi
    if ((created)); then "$work/textedit" close >/dev/null 2>&1 || true; fi
    if ((launched && !was_running)); then "$work/textedit" quit >/dev/null 2>&1 || true; fi
    if ((clipboard_saved)); then "$work/textedit" restore-clipboard "$work/clipboard.plist" || { echo "FAIL: could not restore clipboard" >&2; status=1; }; fi
    rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT
swiftc scripts/e2e-hotkey.swift -o "$work/hotkey"
swiftc scripts/e2e-textedit.swift -o "$work/textedit"
pgrep -f "$HOME/Applications/LightTTS.app/Contents/MacOS/LightTTS" >/dev/null || { echo 'FAIL: installed app is not running' >&2; exit 1; }
"$work/textedit" save-clipboard "$work/clipboard.plist"
clipboard_saved=1
say -o "$work/speech.aiff" 'The quick brown fox jumps over the lazy dog today.'
open -a TextEdit
launched=1
"$work/textedit" new >/dev/null
created=1
sleep 1
"$work/hotkey"
sleep 1
afplay "$work/speech.aiff"
# One process sends stop and polls TextEdit at 20 ms intervals.
"$work/textedit" stop-and-wait
