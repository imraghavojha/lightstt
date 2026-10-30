#!/bin/bash
# --destination is intended for isolated verification; --no-launch avoids starting an app.
set -euo pipefail
cd "$(dirname "$0")/.."
dest="$HOME/Applications/LightTTS.app"
launch=1
while (($#)); do
    case "$1" in
        --destination) dest="$2"; shift 2;;
        --no-launch) launch=0; shift;;
        *) echo "Usage: $0 [--destination /path/LightTTS.app] [--no-launch]" >&2; exit 2;;
    esac
done
mkdir -p "$(dirname "$dest")"
stage=$(mktemp -d "$(dirname "$dest")/.lighttts-install.XXXXXX")
trap 'rm -rf "$stage"' EXIT
scripts/setup-signing.sh
LIGHTTTS_BUILD_CONFIGURATION=release LIGHTTTS_APP_OUTPUT="$stage/LightTTS.app" scripts/build-app.sh
expected='designated => identifier "com.lighttts.app" and certificate leaf = H"a724f6248da5926127de1748fc9ec01c60644679"'
verify() { codesign --verify --deep --strict "$1"; [[ "$(codesign -d -r- "$1" 2>&1 | tail -1)" == "$expected" ]]; }
verify "$stage/LightTTS.app"
# Only stop the exact app at the destination, never another copy with the same bundle ID.
swift - "$dest" <<'SWIFT'
import AppKit
import Foundation
let path = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == path }
for app in apps { guard app.terminate() else { fatalError("Cannot terminate \(path)") } }
for _ in 0..<100 {
    if apps.allSatisfy({ $0.isTerminated }) { exit(0) }
    Thread.sleep(forTimeInterval: 0.1)
}
fatalError("Timed out waiting for \(path) to quit")
SWIFT
# renamex_np exchanges existing directories atomically on the same filesystem.
python3 - "$stage/LightTTS.app" "$dest" <<'PY'
import ctypes, os, sys
src, dest = sys.argv[1:]
if not os.path.lexists(dest):
    os.rename(src, dest)
else:
    libc = ctypes.CDLL(None, use_errno=True)
    if libc.renamex_np(os.fsencode(src), os.fsencode(dest), 2):
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err))
PY
verify "$dest"
if ((launch)); then open "$dest"; fi
verify "$dest"
echo "Installed and verified: $dest"
