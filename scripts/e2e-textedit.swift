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
