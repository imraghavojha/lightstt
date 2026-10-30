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
say -o "$work/speech.aiff" 'The quick brown fox jumps over the lazy dog.'
open -a TextEdit
launched=1
"$work/textedit" new >/dev/null
created=1
sleep 1
"$work/hotkey"
sleep 1
afplay "$work/speech.aiff"
start=$(python3 -c 'import time; print(time.monotonic_ns())')
"$work/hotkey"
for ((i=0; i<240; i++)); do
    "$work/textedit" text > "$work/transcript.txt"
    if python3 - "$work/transcript.txt" <<'PYMATCH'
import difflib, re, sys
expected = re.findall(r"\w+", "the quick brown fox jumps over the lazy dog".casefold())
actual = re.findall(r"\w+", open(sys.argv[1], encoding="utf-8").read().casefold())
matched = 0
for word in expected:
    candidates = [(difflib.SequenceMatcher(None, word, candidate).ratio(), i)
                  for i, candidate in enumerate(actual)]
    if candidates:
        score, index = max(candidates)
        if score >= 0.65:
            matched += 1
            actual.pop(index)
sys.exit(0 if matched / len(expected) >= 0.8 else 1)
PYMATCH
    then
        end=$(python3 -c 'import time; print(time.monotonic_ns())')
        echo "PASS: transcription appeared $(((end-start)/1000000)) ms after stop"
        exit 0
    fi
    sleep 0.5
done
echo 'FAIL: transcription not found within 120 seconds' >&2
exit 1
