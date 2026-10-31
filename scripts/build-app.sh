#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${LIGHTTTS_BUILD_CONFIGURATION:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${LIGHTTTS_APP_OUTPUT:-$PWD/build/LightTTS.app}"
[[ "$APP" != "$HOME/Applications/LightTTS.app" ]] || { echo "Use scripts/install.sh to install the app." >&2; exit 1; }
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN/LightTTS" "$APP/Contents/MacOS/LightTTS"
cp "$BIN/LightTTSEngine" "$APP/Contents/Helpers/LightTTSEngine"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/Helpers/LightTTSEngine"
for bundle in "$BIN"/*.bundle; do [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"; done
for framework in "$BIN"/*.framework; do
    [ -e "$framework" ] || continue
    name="$(basename "$framework")"
    if otool -L "$BIN/LightTTS" "$BIN/LightTTSEngine" | grep -Fq "@rpath/$name/"; then cp -R "$framework" "$APP/Contents/Frameworks/"; fi
done
# Optimize only staged release code, leaving SwiftPM products and debug symbols intact.
if [[ "$CONFIG" == "release" ]]; then
    for executable in "$APP/Contents/MacOS/LightTTS" "$APP/Contents/Helpers/LightTTSEngine"; do
        [[ "$(lipo -archs "$executable")" == "arm64" ]] || { echo "Unsupported executable architecture: $executable" >&2; exit 1; }
        xcrun strip -S -x "$executable"
    done
    whisper="$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper"
    if [[ -f "$whisper" ]]; then
        archs="$(lipo -archs "$whisper")"
        case " $archs " in
            *" arm64 "*) ;;
            *) echo "Unsupported whisper framework architectures: $archs" >&2; exit 1 ;;
        esac
        if [[ "$archs" != "arm64" ]]; then
            # Write to a temporary sibling so the framework's symlinks remain intact.
            thin="$(mktemp "${whisper}.thin.XXXXXX")"
            if ! lipo "$whisper" -thin arm64 -output "$thin"; then
                rm -f "$thin"
                exit 1
            fi
            chmod "$(stat -f '%Lp' "$whisper")" "$thin"
            mv -f "$thin" "$whisper"
        fi
    fi
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>LightTTS</string><key>CFBundleIdentifier</key><string>com.lighttts.app</string><key>CFBundleName</key><string>LightTTS</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>0.1</string><key>LSMinimumSystemVersion</key><string>14.2</string><key>LSUIElement</key><true/><key>NSAppleEventsUsageDescription</key><string>LightTTS pauses and resumes supported audio players while you record.</string><key>NSMicrophoneUsageDescription</key><string>LightTTS records speech for local transcription.</string><key>NSSpeechRecognitionUsageDescription</key><string>LightTTS uses on-device Apple Speech for transcription.</string></dict></plist>
PLIST
if [[ "$CONFIG" == "debug" ]]; then
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes array' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0 dict' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string lighttts' "$APP/Contents/Info.plist"
fi
if [[ "${LIGHTTTS_TEST_ADHOC:-0}" == "1" ]]; then
    if [[ -d "$APP/Contents/Frameworks/whisper.framework" ]]; then
        codesign --force --sign - "$APP/Contents/Frameworks/whisper.framework"
    fi
    codesign --force --deep --sign - "$APP"
    codesign --verify --deep --strict "$APP"
    echo "$APP"
    exit 0
fi
KEYCHAIN="$HOME/Library/Keychains/lighttts-signing.keychain-db"
security unlock-keychain -p lighttts-local "$KEYCHAIN"
HASH="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/"LightTTS Dev Signing"/ {print $2; exit}')"
[[ "$HASH" == A724F6248DA5926127DE1748FC9EC01C60644679 ]] || { echo "LightTTS signing identity is missing; run scripts/setup-signing.sh." >&2; exit 1; }
if [[ -d "$APP/Contents/Frameworks/whisper.framework" ]]; then
    codesign --force --sign "$HASH" --keychain "$KEYCHAIN" "$APP/Contents/Frameworks/whisper.framework"
fi
codesign --force --sign "$HASH" --keychain "$KEYCHAIN" "$APP/Contents/Helpers/LightTTSEngine"
codesign --force --deep --sign "$HASH" --keychain "$KEYCHAIN" "$APP"
codesign --force --sign "$HASH" --keychain "$KEYCHAIN" --requirements "=designated => identifier \"com.lighttts.app\" and certificate leaf = H\"$HASH\"" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
