#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc Sources/LightTTS/TextInputPolicy.swift Tests/ReviewChecks/main.swift -o "$tmp/text-check"
"$tmp/text-check"
python3 - "$tmp" <<'PY'
import pathlib, sys
source = pathlib.Path('Sources/LightTTS/AppController.swift').read_text()
method = source.split('    private func handleShortcut(_ down: Bool) {', 1)[1].split('    private func handlePush', 1)[0]
script = '''import Foundation
class Probe {
 var pressed = false; var shortcutOwnsRecording = false; var state = "idle"; var stops = 0; var cancels = 0
 func start() { state = "recording" }; func stop() { stops += 1; state = "idle" }; func cancel() { cancels += 1; state = "idle" }
 func handleShortcut(_ down: Bool) {''' + method + '''
}
UserDefaults.standard.set(true, forKey: "pushToTalk")
let p = Probe(); p.handleShortcut(true); p.handleShortcut(false); precondition(p.stops == 1 && p.state == "idle")
p.handleShortcut(true); p.handleShortcut(false); precondition(p.stops == 2 && p.state == "idle")
p.handleShortcut(true); p.state = "starting"; p.handleShortcut(false); precondition(p.cancels == 1 && p.state == "idle")
print("push-to-talk release checks passed")
'''
pathlib.Path(sys.argv[1], 'push.swift').write_text(script)
ui = pathlib.Path('Sources/LightTTS/Views/Settings/SettingsView.swift').read_text()
assert 'Pause (Unavailable)' in ui and '.disabled(value == "Pause")' in ui
assert 'func pausePlaying() throws -> [String] { [] }' in pathlib.Path('Sources/LightTTS/AudioSettings.swift').read_text()
print('unavailable Pause option check passed')
PY
swift "$tmp/push.swift"
