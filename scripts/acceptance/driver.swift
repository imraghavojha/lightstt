import AppKit
import ApplicationServices
import Carbon

let args = CommandLine.arguments
let pb = NSPasteboard.general
func fail(_ message: String) -> Never { fputs("\(message)\n", stderr); exit(1) }
func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags = []) {
    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { fail("Cannot create HID event") }
    e.flags = flags; e.post(tap: .cghidEventTap); usleep(50000)
}
switch args[1] {
case "script":
    var error: NSDictionary?
    guard let script = NSAppleScript(source: args[2]) else { fail("Invalid AppleScript") }
    let result = script.executeAndReturnError(&error)
    if let error { fail("AppleScript: \(error)") }; print(result.stringValue ?? "")
case "trust":
    exit(AXIsProcessTrusted() ? 0 : 1)
case "automation":
    let target = NSAppleEventDescriptor(bundleIdentifier: args[2])
    exit(AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false) == noErr ? 0 : 1)
case "save":
    let items: [[String: Data]] = (pb.pasteboardItems ?? []).map { item in
        var data: [String: Data] = [:]
        for type in item.types { if let value = item.data(forType: type) { data[type.rawValue] = value } }
        return data
    }
    let data = try PropertyListEncoder().encode(items); try data.write(to: URL(fileURLWithPath: args[2]))
case "restore":
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let items = try PropertyListDecoder().decode([[String: Data]].self, from: data).map { values -> NSPasteboardItem in
        let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }; return item
    }
    pb.clearContents(); if !items.isEmpty { pb.writeObjects(items) }
case "set": pb.clearContents(); pb.setString(args[2], forType: .string)
case "get": print(pb.string(forType: .string) ?? "")
case "key":
    let code = CGKeyCode(args[2])!; let flags = CGEventFlags(rawValue: UInt64(args[3])!)
    let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
    var held: CGEventFlags = []
    for (flag, key) in modifiers where flags.contains(flag) { held.insert(flag); post(key, true, held) }
    post(code, true, held); post(code, false, held)
    for (flag, key) in modifiers.reversed() where flags.contains(flag) { held.remove(flag); post(key, false, held) }
case "right-option": post(61, true, .maskAlternate); post(61, false)
case "desktop":
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { fail("Cannot enumerate windows") }
    let rects: [CGRect] = windows.compactMap { w in
        guard (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              (w[kCGWindowLayer as String] as? Int ?? -1) >= 0,
              let bounds = w[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
    let screen = CGDisplayBounds(CGMainDisplayID())
    var point: CGPoint?
    for x in stride(from: screen.minX + 30, through: screen.maxX - 30, by: 45) {
        for y in stride(from: screen.minY + 50, through: screen.maxY - 80, by: 45) {
            let candidate = CGPoint(x: x, y: y)
            if !rects.contains(where: { $0.contains(candidate) }) { point = candidate; break }
        }
        if point != nil { break }
    }
    guard let point else { fail("No uncovered desktop point") }
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { fail("Cannot create mouse event") }
        e.post(tap: .cghidEventTap); usleep(50000)
    }
case "windows":
    guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { fail("Cannot enumerate windows") }
    let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.lighttts.app").map { Int($0.processIdentifier) })
    let found = windows.filter { pids.contains($0[kCGWindowOwnerPID as String] as? Int ?? -1) && ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0 && ($0[kCGWindowLayer as String] as? Int ?? 0) >= 0 }
    print(found.count)
    for w in found { fputs("window: \(w[kCGWindowName as String] ?? "<untitled>")\n", stderr) }
default: fail("Unknown command")
}
