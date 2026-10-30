#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --target LightTTS
BIN="$(swift build --show-bin-path)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/resources.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static let module = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("LightTTS_LightTTS.bundle"))!
}
SWIFT
swiftc -parse-as-library "$TMP/resources.swift" -I "$BIN" "$BIN/LightTTSCore.o" "$BIN/CoreAudioTapKit.o" $(find Sources/LightTTS -name '*.swift' ! -name LightTTSApp.swift) Tests/LightTTSTests/HelperFailureChecks.swift -o "$TMP/checks"
cp -R "$BIN/LightTTS_LightTTSCore.bundle" "$BIN/LightTTS_LightTTS.bundle" "$TMP/"
"$TMP/checks"
