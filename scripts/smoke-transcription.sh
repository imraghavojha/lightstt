#!/bin/bash
# Requires pre-granted Accessibility and TextEdit automation access and installed models.
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d "${TMPDIR:-/tmp}/lighttts-smoke.XXXXXX")"
pid=''
cleanup() {
    if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    rm -rf "$work"
}
trap cleanup EXIT
LIGHTTTS_BUILD_CONFIGURATION=debug scripts/build-app.sh
say -o "$work/speech.aiff" 'The quick brown fox jumps over the lazy dog.'
afconvert "$work/speech.aiff" "$work/speech.wav" -f WAVE -d LEI16@16000 -c 1
for model in whisper-tiny.en parakeet-v3; do
    osascript -e 'tell application "TextEdit" to make new document' -e 'tell application "TextEdit" to activate' >/dev/null
    LIGHTTTS_TEST_AUDIO="$work/speech.wav" LIGHTTTS_TEST_PASTE=1 LIGHTTTS_TEST_MODEL="$model" LIGHTTTS_TEST_TRACE=1 LIGHTTTS_LAUNCH_MARKER="$work/ready" "$HOME/Applications/LightTTS.app/Contents/MacOS/LightTTS" >"$work/$model.log" 2>&1 &
    pid=$!
    for ((i=0; i<60; i++)); do [[ -f "$work/ready" ]] && break; kill -0 "$pid"; sleep 1; done
    [[ -f "$work/ready" ]] || { cat "$work/$model.log"; exit 1; }
    swift scripts/test-trigger.swift "$pid" toggle
    sleep 4
    swift scripts/test-trigger.swift "$pid" toggle
    found=0
    for ((i=0; i<120; i++)); do
        if osascript -e 'tell application "TextEdit" to get text of front document' | grep -iq 'quick brown fox'; then found=1; break; fi
        kill -0 "$pid" || break
        sleep 1
    done
    cat "$work/$model.log"
    [[ "$found" == 1 ]] || { echo "$model: transcription failed" >&2; exit 1; }
    echo "$model: TextEdit transcription passed"
    kill "$pid"; wait "$pid" || true; pid=''
    rm -f "$work/ready"
done
