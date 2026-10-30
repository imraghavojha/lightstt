#!/bin/bash
# Headless checks only: no app, microphone, screen, clipboard, or media control.
set -euo pipefail
cd "$(dirname "$0")/.."
start=$SECONDS
work="$(mktemp -d "${TMPDIR:-/tmp}/lighttts-check.XXXXXX")"
trap 'rm -rf "$work"' EXIT
say -o "$work/speech.aiff" 'The quick brown fox jumps over the lazy dog.'
afconvert "$work/speech.aiff" "$work/speech.wav" -f WAVE -d LEI16@16000 -c 1
swiftc -emit-library -emit-module -module-name LightTTSCore Sources/LightTTSCore/SpeechError.swift Sources/LightTTSCore/AudioFileReader.swift -emit-module-path "$work/LightTTSCore.swiftmodule" -o "$work/libLightTTSCore.dylib"
swiftc -I "$work" -L "$work" -lLightTTSCore -Xlinker -rpath -Xlinker "$work" Sources/LightTTS/AudioCapture.swift Sources/LightTTS/TextInputPolicy.swift Tests/HeadlessCoreFlow/main.swift -o "$work/core-check"
LIGHTTTS_TEST_AUDIO="$work/speech.wav" "$work/core-check" "$work/speech.aiff" "$work/speech.pcm"
scripts/test-audio-processing.sh
model="$HOME/Library/Application Support/LightTTS/Models/whisper-tiny.en"
if [[ -f "$model" ]]; then
    swift build --product LightTTSEngine
    bin="$(swift build --show-bin-path)"
    python3 Tests/HeadlessCoreFlow/helper.py "$bin/LightTTSEngine" "$work/speech.pcm"
else
    echo 'SKIP: Whisper Tiny EN helper transcription and latency (model not downloaded)'
fi
echo 'SKIP: toggle/push/cancel, raw-input classification, secure/editable target and clipboard restore, and volume restore (production seams absent; see Tests/HeadlessCoreFlow/README.md)'
printf 'Available headless checks passed in %s seconds (see SKIP lines for unavailable coverage).\n' "$((SECONDS - start))"
