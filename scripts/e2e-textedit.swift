import AppKit
import ApplicationServices
import Foundation
// Preserve all pasteboard items and representations, not just plain text.
struct ClipboardItem: Codable { let values: [String: Data] }
if CommandLine.arguments.count == 3 {
    let path = URL(fileURLWithPath: CommandLine.arguments[2])
    let pasteboard = NSPasteboard.general
    do {
        switch CommandLine.arguments[1] {
        case "save-clipboard":
            let items = (pasteboard.pasteboardItems ?? []).map { item in
                ClipboardItem(values: Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type.rawValue, $0) }
                }))
            }
            try PropertyListEncoder().encode(items).write(to: path)
        case "restore-clipboard":
            let items = try PropertyListDecoder().decode([ClipboardItem].self, from: Data(contentsOf: path))
            let restored = items.map { saved -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in saved.values { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
                return item
            }
            pasteboard.clearContents()
            if !restored.isEmpty && !pasteboard.writeObjects(restored) { throw CocoaError(.fileWriteUnknown) }
        default: exit(2)
        }
    } catch { fputs("Clipboard operation failed: \(error)\n", stderr); exit(1) }
    exit(0)
}
// Preflight in the same process that sends Apple events; never request consent.
let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.TextEdit")
var status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
// Launch Services can return before TextEdit is ready to receive Apple events.
for _ in 0..<100 where status == procNotFound {
    Thread.sleep(forTimeInterval: 0.1)
    status = AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), false)
}
guard status == noErr else { fputs("TextEdit automation permission is required (status \(status)).\n", stderr); exit(1) }
// Measure from the stop key event in the same long-lived process that polls TextEdit.
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "stop-and-wait" {
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { fputs("Accessibility access is required.\n", stderr); exit(1) }
    let defaults = UserDefaults(suiteName: "com.lighttts.app")!
    guard !defaults.bool(forKey: "rightOption"), !defaults.bool(forKey: "pushToTalk") else { fputs("Configure a toggle shortcut.\n", stderr); exit(1) }
    let key = CGKeyCode(defaults.object(forKey: "hotkeyCode") as? Int ?? 49)
    let flags = CGEventFlags(rawValue: UInt64(defaults.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.option.rawValue)))
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false),
          let script = NSAppleScript(source: "with timeout of 1 second\n tell application \"TextEdit\" to get text of front document\nend timeout") else { exit(1) }
    down.flags = flags; up.flags = flags
    let start = ProcessInfo.processInfo.systemUptime
    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
    let expected = ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog", "today"]
    while ProcessInfo.processInfo.systemUptime - start < 120 {
        var error: NSDictionary?
        let text = script.executeAndReturnError(&error).stringValue ?? ""
        if let error { fputs("TextEdit automation failed: \(error)\n", stderr); exit(1) }
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var remaining = words
        var matched = 0
        for word in expected { if let index = remaining.firstIndex(of: word) { matched += 1; remaining.remove(at: index) } }
        if matched >= 8 {
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            print("PASS: transcription appeared \(Int(elapsed)) ms after stop")
            exit(0)
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    fputs("FAIL: transcription not found within 120 seconds\n", stderr); exit(1)
}
let scripts = [
    "new": "tell application \"TextEdit\" to make new document\ntell application \"TextEdit\" to activate",
    "text": "tell application \"TextEdit\" to get text of front document",
    "close": "tell application \"TextEdit\" to close front document saving no",
    "quit": "tell application \"TextEdit\" to quit saving no"
]
guard CommandLine.arguments.count == 2, let source = scripts[CommandLine.arguments[1]], let script = NSAppleScript(source: source) else { exit(2) }
var error: NSDictionary?
let result = script.executeAndReturnError(&error)
if let error { fputs("TextEdit automation failed: \(error)\n", stderr); exit(1) }
if let value = result.stringValue { print(value) }
