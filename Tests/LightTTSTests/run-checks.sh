#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --target LightTTS
BIN="$(swift build --show-bin-path)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swiftc -parse-as-library -I "$BIN" "$BIN/LightTTSCore.o" $(find Sources/LightTTS -name '*.swift' ! -name LightTTSApp.swift) Tests/LightTTSTests/HelperFailureChecks.swift -o "$TMP/checks"
cp -R "$BIN/LightTTS_LightTTSCore.bundle" "$TMP/"
"$TMP/checks"
