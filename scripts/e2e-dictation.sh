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
# Bound each Apple event as well as the polling loop by the same monotonic deadline.
python3 - "$work/hotkey" "$work/textedit" <<'PYWAIT'
import difflib, re, subprocess, sys, time

hotkey, textedit = sys.argv[1:]
start = time.monotonic()
deadline = start + 120
expected = re.findall(r"\w+", "the quick brown fox jumps over the lazy dog".casefold())
try:
    subprocess.run([hotkey], check=True, timeout=max(0.001, deadline - time.monotonic()))
    while time.monotonic() < deadline:
        result = subprocess.run([textedit, "text"], check=True, capture_output=True, text=True,
                                timeout=max(0.001, deadline - time.monotonic()))
        appeared = time.monotonic()
        actual = re.findall(r"\w+", result.stdout.casefold())
        matched = 0
        for word in expected:
            candidates = [(difflib.SequenceMatcher(None, word, candidate).ratio(), i)
                          for i, candidate in enumerate(actual)]
            if candidates:
                score, index = max(candidates)
                if score >= 0.65:
                    matched += 1
                    actual.pop(index)
        if matched / len(expected) >= 0.8 and appeared <= deadline:
            print(f"PASS: transcription appeared {int((appeared - start) * 1000)} ms after stop")
            sys.exit(0)
        time.sleep(min(0.5, max(0, deadline - time.monotonic())))
except subprocess.TimeoutExpired:
    pass
except subprocess.CalledProcessError as error:
    print(f"FAIL: command failed: {error}", file=sys.stderr)
    sys.exit(1)
print("FAIL: transcription not found within 120 seconds", file=sys.stderr)
sys.exit(1)
PYWAIT
