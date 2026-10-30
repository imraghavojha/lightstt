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
# Export only the existing certificate; never generate or replace the identity.
cert=$(mktemp -t lighttts-signing-cert.XXXXXX)
trap 'rm -f "$cert"' EXIT
security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$cert"
fingerprint=$(openssl x509 -in "$cert" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
if [[ "$fingerprint" != "$EXPECTED" ]]; then
    echo "Exported certificate does not match the required identity." >&2
    exit 1
fi
if ! security verify-cert -c "$cert" -p codeSign >/dev/null 2>&1; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$cert"
    security verify-cert -c "$cert" -p codeSign
fi
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
echo "Signing identity available: $NAME ($EXPECTED)"
