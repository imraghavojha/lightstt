import AppKit
import ApplicationServices
import AVFoundation
import Carbon

let args = CommandLine.arguments
let pb = NSPasteboard.general
func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}
func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags = []) {
    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
        fail("Cannot create HID event")
    }
    e.flags = flags
    e.post(tap: .cghidEventTap)
    usleep(50000)
}
switch args[1] {
case "trust":
    exit(AXIsProcessTrusted() ? 0 : 1)
case "permissions":
    exit(
        CGPreflightScreenCaptureAccess()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? 0 : 1)
case "superwhisper-path":
    for app in NSWorkspace.shared.runningApplications
    where app.localizedName?.lowercased() == "superwhisper" {
        if let url = app.bundleURL { print(url.path) }
    }
case "quit-superwhisper":
    let apps = NSWorkspace.shared.runningApplications.filter {
        $0.localizedName?.lowercased() == "superwhisper"
    }
    for app in apps { _ = app.terminate() }
    for _ in 0..<30 {
        if apps.allSatisfy({ kill($0.processIdentifier, 0) != 0 && errno == ESRCH }) { exit(0) }
        usleep(100000)
    }
    for app in apps where kill(app.processIdentifier, 0) == 0 { _ = app.forceTerminate() }
    for _ in 0..<50 {
        if apps.allSatisfy({ kill($0.processIdentifier, 0) != 0 && errno == ESRCH }) { exit(0) }
        usleep(100000)
    }
    fail("SuperWhisper did not quit")
case "notes-back":
    guard
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Notes")
            .first
    else { fail("Notes unavailable") }
    func find(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
        guard depth < 30 else { return nil }
        var description: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
        if description as? String == "Back" { return element }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in (children as? [AXUIElement] ?? []) {
            if let result = find(child, depth + 1) { return result }
        }
        return nil
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard let back = find(root, 0),
        AXUIElementPerformAction(back, kAXPressAction as CFString) == .success
    else { fail("Cannot leave test note") }
case "focus":
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first
    else { fail("Target application is not running") }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value : nil
    }
    func find(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
        guard depth < 30 else { return nil }
        let role = attribute(element, kAXRoleAttribute) as? String ?? ""
        if [kAXTextAreaRole, kAXTextFieldRole].contains(role),
            attribute(element, kAXSizeAttribute) != nil
        {
            return element
        }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
            if let found = find(child, depth + 1) { return found }
        }
        return nil
    }
    guard let window = attribute(root, kAXFocusedWindowAttribute) else { fail("No focused window") }
    let windowElement = window as! AXUIElement
    let focused = attribute(root, kAXFocusedUIElementAttribute) as! AXUIElement?
    let focusedRole = focused.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? ""
    let target =
        [kAXTextAreaRole, kAXTextFieldRole].contains(focusedRole)
        ? focused! : (find(windowElement, 0) ?? windowElement)
    guard let position = attribute(target, kAXPositionAttribute),
        let size = attribute(target, kAXSizeAttribute)
    else { fail("No target bounds") }
    var point = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
        AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
    else { fail("Invalid bounds") }
    point.x += min(dimensions.width / 2, 150)
    point.y += min(dimensions.height / 2, 100)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: point, mouseButton: .left)
        else { fail("Cannot create mouse event") }
        event.post(tap: .cghidEventTap)
        usleep(50000)
    }
case "save":
    let items: [[String: Data]] = (pb.pasteboardItems ?? []).map { item in
        var data: [String: Data] = [:]
        for type in item.types {
            if let value = item.data(forType: type) { data[type.rawValue] = value }
        }
        return data
    }
    let data = try PropertyListEncoder().encode(items)
    try data.write(to: URL(fileURLWithPath: args[2]))
case "restore":
    let data = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let items = try PropertyListDecoder().decode([[String: Data]].self, from: data).map {
        values -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in values {
            item.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
        return item
    }
    pb.clearContents()
    if !items.isEmpty { pb.writeObjects(items) }
case "set":
    pb.clearContents()
    pb.setString(args[2], forType: .string)
case "get": print(pb.string(forType: .string) ?? "")
case "key":
    let code = CGKeyCode(args[2])!
    let flags = CGEventFlags(rawValue: UInt64(args[3])!)
    let modifiers: [(CGEventFlags, CGKeyCode)] = [
        (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55),
    ]
    var held: CGEventFlags = []
    for (flag, key) in modifiers where flags.contains(flag) {
        held.insert(flag)
        post(key, true, held)
    }
    post(code, true, held)
    post(code, false, held)
    for (flag, key) in modifiers.reversed() where flags.contains(flag) {
        held.remove(flag)
        post(key, false, held)
    }
case "right-option":
    post(61, true, .maskAlternate)
    post(61, false)
case "desktop":
    guard
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { fail("Cannot enumerate windows") }
    let rects: [CGRect] = windows.compactMap { w in
        guard (w[kCGWindowAlpha as String] as? Double ?? 0) > 0,
            (w[kCGWindowLayer as String] as? Int ?? -1) >= 0,
            let bounds = w[kCGWindowBounds as String] as? [String: Any]
        else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
    let screen = CGDisplayBounds(CGMainDisplayID())
    var point: CGPoint?
    for x in stride(from: screen.minX + 30, through: screen.maxX - 30, by: 45) {
        for y in stride(from: screen.minY + 50, through: screen.maxY - 80, by: 45) {
            let candidate = CGPoint(x: x, y: y)
            if !rects.contains(where: { $0.contains(candidate) }) {
                point = candidate
                break
            }
        }
        if point != nil { break }
    }
    guard let point else { fail("No uncovered desktop point") }
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard
            let e = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                mouseButton: .left)
        else { fail("Cannot create mouse event") }
        e.post(tap: .cghidEventTap)
        usleep(50000)
    }
case "windows":
    guard
        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { fail("Cannot enumerate windows") }
    let pids = Set(
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.lighttts.app").map {
            Int($0.processIdentifier)
        })
    let found = windows.filter {
        pids.contains($0[kCGWindowOwnerPID as String] as? Int ?? -1)
            && ($0[kCGWindowAlpha as String] as? Double ?? 0) > 0
            && ($0[kCGWindowLayer as String] as? Int ?? 0) >= 0
    }
    print(found.count)
    for w in found { fputs("window: \(w[kCGWindowName as String] ?? "<untitled>")\n", stderr) }
default: fail("Unknown command")
}
