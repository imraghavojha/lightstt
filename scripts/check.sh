#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
swift build
swift test
scripts/test-audio-processing.sh
Tests/LightTTSTests/run-checks.sh
# The cloud helper check uses a local mock and a generated PCM fixture.
say -o "$tmp/speech.aiff" 'Hello from LightTTS.'
afconvert "$tmp/speech.aiff" "$tmp/speech.wav" -f WAVE -d LEI16@16000 -c 1
python3 scripts/test-helper-cloud.py "$(swift build --show-bin-path)/LightTTSEngine" "$tmp/speech.wav"
say -o "$tmp/regression.aiff" 'The quick brown fox jumps over the lazy dog.'
afconvert "$tmp/regression.aiff" "$tmp/regression.wav" -f WAVE -d LEI16@16000 -c 1
python3 scripts/test-helper-transcription.py "$(swift build --show-bin-path)/LightTTSEngine" "$tmp/regression.wav"
