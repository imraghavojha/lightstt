#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/lighttts-audio-test.XXXXXX")"
trap 'rm -f "$test_dir/check"; rmdir "$test_dir"' EXIT
swiftc Sources/LightTTS/AudioProcessing.swift Sources/LightTTS/MediaPauseSession.swift Tests/AudioProcessingChecks/main.swift -o "$test_dir/check"
"$test_dir/check"
