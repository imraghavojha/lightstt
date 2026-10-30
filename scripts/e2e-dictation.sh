#!/bin/bash
# Requires existing microphone, Accessibility, Input Monitoring, and TextEdit automation grants.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-e2e.XXXXXX")
created=0
was_running=0
pgrep -x TextEdit >/dev/null && was_running=1
cleanup() {
    status=$?
    if ((status)); then echo "FAIL: e2e exited with status $status" >&2; fi
    if ((created)); then "$work/textedit" close >/dev/null 2>&1 || true; fi
    if ((created && !was_running)); then "$work/textedit" quit >/dev/null 2>&1 || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
swiftc scripts/e2e-hotkey.swift -o "$work/hotkey"
swiftc scripts/e2e-textedit.swift -o "$work/textedit"
pgrep -f "$HOME/Applications/LightTTS.app/Contents/MacOS/LightTTS" >/dev/null || { echo 'FAIL: installed app is not running' >&2; exit 1; }
say -o "$work/speech.aiff" 'The quick brown fox jumps over the lazy dog.'
"$work/textedit" new >/dev/null
created=1
sleep 1
"$work/hotkey"
sleep 1
afplay "$work/speech.aiff"
start=$(python3 -c 'import time; print(time.monotonic_ns())')
"$work/hotkey"
for ((i=0; i<120; i++)); do
    if "$work/textedit" text | grep -iq 'quick brown fox'; then
        end=$(python3 -c 'import time; print(time.monotonic_ns())')
        echo "PASS: $(((end-start)/1000000)) ms"
        exit 0
    fi
    sleep 1
done
echo 'FAIL: transcription not found within 120 seconds' >&2
exit 1
