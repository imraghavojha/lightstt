#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
swift build --target LightTTS
BIN="$(swift build --show-bin-path)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/resource_bundle_accessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static let module = Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("LightTTS_LightTTS.bundle"))!
}
SWIFT
swiftc -parse-as-library -I "$BIN" "$BIN/LightTTSCore.o" $(find Sources/LightTTS -name '*.swift' ! -name LightTTSApp.swift) "$TMP/resource_bundle_accessor.swift" Tests/LightTTSTests/HelperFailureChecks.swift -o "$TMP/checks"
cp -R "$BIN/LightTTS_LightTTSCore.bundle" "$BIN/LightTTS_LightTTS.bundle" "$TMP/"
"$TMP/checks"
