#!/bin/bash
set -euo pipefail
NAME='LightTTS Dev Signing'
KEYCHAIN="$HOME/Library/Keychains/lighttts-signing.keychain-db"
PASSWORD='lighttts-local'
CERT_DIR="$HOME/Library/Application Support/LightTTS-Signing"
# A newly generated certificate changes the designated requirement and loses permissions.
EXPECTED=A724F6248DA5926127DE1748FC9EC01C60644679
if [[ ! -f "$KEYCHAIN" ]] || ! security find-identity -p codesigning "$KEYCHAIN" | grep -Fq "$EXPECTED "; then
    echo "Required signing identity $EXPECTED is missing; restore the original keychain." >&2
    exit 1
fi
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
echo "Signing identity available: $NAME ($EXPECTED)"
