import AppKit
import ApplicationServices
import Foundation
// Fail without requesting Accessibility access.
guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
    fputs("Accessibility access is required for the verifier.\n", stderr); exit(1)
}
let defaults = UserDefaults(suiteName: "com.lighttts.app")!
if defaults.bool(forKey: "rightOption") || defaults.bool(forKey: "pushToTalk") {
    fputs("Configure a toggle shortcut before running this check.\n", stderr); exit(1)
}
let key = CGKeyCode(defaults.object(forKey: "hotkeyCode") as? Int ?? 49)
let flags = CGEventFlags(rawValue: UInt64(defaults.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.option.rawValue)))
for down in [true, false] {
    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { exit(1) }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(100_000)
}
