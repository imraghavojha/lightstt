#!/bin/bash
set -euo pipefail
NAME='LightTTS Local Signing'
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$NAME\""; then
    if [[ -n "${LIGHTTTS_KEYCHAIN_PASSWORD:-}" ]]; then
        if ! security find-key -l "$NAME" -t private "$KEYCHAIN" >/dev/null 2>&1; then
            echo "The private key is not uniquely labeled; approve codesign in Keychain Access before setting partitions." >&2
            exit 1
        fi
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" -k "$LIGHTTTS_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
    fi
    echo "Signing identity already available: $NAME (codesign key access may still require Keychain authorization)."
    exit 0
fi
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lighttts-signing.XXXXXX")"
trap 'rm -f "$TMP_DIR/key.pem" "$TMP_DIR/cert.pem" "$TMP_DIR/identity.p12" "$TMP_DIR/openssl.cnf"; rmdir "$TMP_DIR"' EXIT
cat > "$TMP_DIR/openssl.cnf" <<'CONF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = extensions
[dn]
CN = LightTTS Local Signing
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
CONF
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 3650 -config "$TMP_DIR/openssl.cnf" -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem" >/dev/null 2>&1
P12_PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 -export -legacy -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" -name "$NAME" -out "$TMP_DIR/identity.p12" -passout "pass:$P12_PASSWORD"
security import "$TMP_DIR/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASSWORD" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP_DIR/cert.pem"
# If a keychain password is supplied explicitly, also set the Apple code-signing partitions.
# Import's codesign ACL works on unlocked login keychains without storing the password.
if [[ -n "${LIGHTTTS_KEYCHAIN_PASSWORD:-}" ]]; then
    if ! security find-key -l "$NAME" -t private "$KEYCHAIN" >/dev/null 2>&1; then
        echo "The imported private key is not uniquely labeled; authorize codesign in Keychain Access." >&2
        exit 1
    fi
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" -k "$LIGHTTTS_KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
fi
security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$NAME\""
echo "Authorize codesign for the key in Keychain Access if macOS requests access."
