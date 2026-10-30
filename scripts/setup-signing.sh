#!/bin/bash
set -euo pipefail
NAME='LightTTS Dev Signing'
KEYCHAIN="$HOME/Library/Keychains/lighttts-signing.keychain-db"
PASSWORD='lighttts-local'
CERT_DIR="$HOME/Library/Application Support/LightTTS-Signing"
if [[ -f "$KEYCHAIN" ]] && security find-identity -p codesigning "$KEYCHAIN" | grep -Fq "\"$NAME\""; then
    echo "Signing identity already available: $NAME"
    exit 0
fi
if [[ -f "$KEYCHAIN" ]]; then
    echo "The signing keychain exists but does not contain $NAME; repair it before continuing." >&2
    exit 1
fi
mkdir -p "$CERT_DIR"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lighttts-signing.XXXXXX")"
cleanup() {
    local status=$?
    trap - EXIT
    rm -f "$TMP_DIR/key.pem" "$TMP_DIR/identity.p12" || true
    rmdir "$TMP_DIR" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT
cat > "$CERT_DIR/cert.cnf" <<'CONF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=LightTTS Dev Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CONF
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 -config "$CERT_DIR/cert.cnf" -keyout "$TMP_DIR/key.pem" -out "$CERT_DIR/cert.pem" >/dev/null 2>&1
# OpenSSL 3 needs -legacy for the PBE algorithms accepted by Keychain; LibreSSL
# provides those algorithms natively and does not recognize -legacy.
PKCS12_FLAGS=(-descert)
if openssl version | grep -Eq '^OpenSSL (3|[4-9])\.'; then PKCS12_FLAGS=(-legacy); fi
openssl pkcs12 -export "${PKCS12_FLAGS[@]}" -inkey "$TMP_DIR/key.pem" -in "$CERT_DIR/cert.pem" -name "$NAME" -out "$TMP_DIR/identity.p12" -passout "pass:$PASSWORD"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$TMP_DIR/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$PASSWORD" -T /usr/bin/codesign -x
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
KEYCHAINS=("$KEYCHAIN")
while IFS= read -r line; do
    line="${line#\"}"; line="${line%\"}"
    [[ -n "$line" && "$line" != "$KEYCHAIN" ]] && KEYCHAINS+=("$line")
done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*//')
security list-keychains -d user -s "${KEYCHAINS[@]:1}" "$KEYCHAIN"
security find-identity -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
