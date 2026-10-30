#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${LIGHTTTS_BUILD_CONFIGURATION:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$PWD/build/LightTTS.app"
INSTALL="$HOME/Applications/LightTTS.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/LightTTS" "$APP/Contents/MacOS/LightTTS"
cp licenses/CoreAudioTapKit-LICENSE "$APP/Contents/Resources/CoreAudioTapKit-LICENSE"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/LightTTS"
for bundle in "$BIN"/*.bundle; do [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"; done
for framework in "$BIN"/*.framework; do [ -e "$framework" ] && cp -R "$framework" "$APP/Contents/Frameworks/"; done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>LightTTS</string><key>CFBundleIdentifier</key><string>com.lighttts.app</string><key>CFBundleName</key><string>LightTTS</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1</string><key>LSMinimumSystemVersion</key><string>14.2</string><key>LSUIElement</key><true/><key>NSAudioCaptureUsageDescription</key><string>LightTTS filters system audio while you record.</string><key>NSAppleEventsUsageDescription</key><string>LightTTS pauses and resumes music while recording.</string><key>NSMicrophoneUsageDescription</key><string>LightTTS records speech for local transcription.</string></dict></plist>
PLIST
if [[ "$CONFIG" == "debug" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string lighttts' "$APP/Contents/Info.plist"
fi
KEYCHAIN="$HOME/Library/Keychains/lighttts-signing.keychain-db"
security unlock-keychain -p lighttts-local "$KEYCHAIN"
HASH="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/"LightTTS Dev Signing"/ {print $2; exit}')"
[[ -n "$HASH" ]] || { echo "LightTTS signing identity is missing; run scripts/setup-signing.sh." >&2; exit 1; }
codesign --force --deep --sign "$HASH" --keychain "$KEYCHAIN" "$APP"
codesign --force --sign "$HASH" --keychain "$KEYCHAIN" --requirements "=designated => identifier \"com.lighttts.app\" and certificate leaf = H\"$HASH\"" "$APP"
mkdir -p "$INSTALL"
rsync -a --delete "$APP/" "$INSTALL/"
codesign --verify --deep --strict "$INSTALL"
echo "$INSTALL"
