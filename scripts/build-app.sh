#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${LIGHTTTS_BUILD_CONFIGURATION:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$PWD/build/LightTTS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/LightTTS" "$APP/Contents/MacOS/LightTTS"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/LightTTS"
for bundle in "$BIN"/*.bundle; do [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"; done
for framework in "$BIN"/*.framework; do [ -e "$framework" ] && cp -R "$framework" "$APP/Contents/Frameworks/"; done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>LightTTS</string><key>CFBundleIdentifier</key><string>com.lighttts.app</string><key>CFBundleName</key><string>LightTTS</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>LSUIElement</key><true/><key>NSMicrophoneUsageDescription</key><string>LightTTS records speech for local transcription.</string></dict></plist>
PLIST
codesign --force --deep --sign "${LIGHTTTS_CODESIGN_IDENTITY:--}" "$APP"
echo "$APP"
