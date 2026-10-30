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
let pids = apps.map(\.processIdentifier)
func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
func signal(_ pid: pid_t, _ sig: Int32) {
    guard alive(pid) else { return }
    if kill(pid, sig) != 0 && errno != ESRCH {
        fatalError("Cannot signal pid \(pid): \(String(cString: strerror(errno)))")
    }
}
for app in apps where alive(app.processIdentifier) {
    if !app.terminate() { fputs("Graceful termination request failed for pid \(app.processIdentifier)\n", stderr) }
}
func waitForExit(_ seconds: Int) -> Bool {
    for _ in 0..<(seconds * 10) {
        if pids.allSatisfy({ !alive($0) }) { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return pids.allSatisfy({ !alive($0) })
}
if !waitForExit(10) {
    for pid in pids { signal(pid, SIGTERM) }
    if !waitForExit(3) {
        for pid in pids { signal(pid, SIGKILL) }
        guard waitForExit(3) else { fatalError("Cannot stop \(path)") }
    }
}
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
