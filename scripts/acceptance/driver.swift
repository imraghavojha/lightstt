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
case "focus", "read", "target-key", "target-option", "close":
    guard args.count >= 4 else { fail("Target application unavailable") }
    let identity = args[3]
    func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value : nil
    }
    func find(_ element: AXUIElement, _ depth: Int, _ predicate: (AXUIElement) -> Bool)
        -> AXUIElement?
    {
        guard depth < 30 else { return nil }
        if predicate(element) { return element }
        for child in (attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
            if let result = find(child, depth + 1, predicate) { return result }
        }
        return nil
    }
    let candidates = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).flatMap
    {
        app -> [(NSRunningApplication, AXUIElement, AXUIElement)] in
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windows = attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
        return windows.filter { (attr($0, kAXTitleAttribute) as? String ?? "").contains(identity) }
            .map { (app, root, $0) }
    }
    guard candidates.count == 1, let (app, root, window) = candidates.first else {
        fail("Expected exactly one window containing \(identity), found \(candidates.count)")
    }
    if args[2] == "com.google.Chrome" {
        _ = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        usleep(1000000)  // Chrome populates the renderer accessibility tree asynchronously.
    }
    if args[1] == "close" {
        guard let button = attr(window, kAXCloseButtonAttribute),
            CFGetTypeID(button) == AXUIElementGetTypeID(),
            AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
        else { fail("Cannot close test window") }
        for _ in 0..<30 {
            usleep(100000)
            let windows = attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            guard
                let current = windows.first(where: {
                    (attr($0, kAXTitleAttribute) as? String ?? "").contains(identity)
                })
            else { exit(0) }
            if let button = find(
                current, 0,
                { element in
                    let title = attr(element, kAXTitleAttribute) as? String ?? ""
                    return (attr(element, kAXRoleAttribute) as? String) == kAXButtonRole
                        && ["Delete", "Don't Save", "Don’t Save"].contains(title)
                })
            {
                _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
            }
        }
        fail("Test window did not close")
    }
    guard app.activate(options: [.activateIgnoringOtherApps]),
        AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    else { fail("Cannot activate and raise test window") }
    func verified() -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
            let focused = attr(root, kAXFocusedWindowAttribute),
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return false }
        return (attr(focused as! AXUIElement, kAXTitleAttribute) as? String ?? "").contains(
            identity)
    }
    for _ in 0..<30 {
        if verified() { break }
        usleep(100000)
    }
    guard verified() else { fail("Frontmost app or focused window identity mismatch") }
    if args[1] == "focus" { exit(0) }
    // Chrome has a text field in its toolbar; only target the page web area.
    let fieldRoot: AXUIElement
    if args[2] == "com.google.Chrome" {
        guard
            let webArea = find(
                window, 0, { (attr($0, kAXRoleAttribute) as? String) == "AXWebArea" }
            )
        else {
            fail("Cannot find Chrome page web area")
        }
        fieldRoot = webArea
    } else {
        fieldRoot = window
    }
    let field = find(fieldRoot, 0) { element in
        let role = attr(element, kAXRoleAttribute) as? String ?? ""
        return [kAXTextAreaRole, kAXTextFieldRole].contains(role)
            && attr(element, kAXValueAttribute) != nil
    }
    if args[1] == "read" {
        guard let field, let value = attr(field, kAXValueAttribute) as? String else {
            fail("Cannot read test field AXValue")
        }
        print(value)
        exit(0)
    }
    if args[1] != "focus" {
        guard let field else { fail("Cannot find test text field") }
        guard
            AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                == .success, verified()
        else { fail("Cannot focus test text field safely") }
        guard let focused = attr(root, kAXFocusedUIElementAttribute),
            CFGetTypeID(focused) == AXUIElementGetTypeID(),
            CFEqual(focused, field)
        else { fail("Focused element is not the test field") }
        if args[1] == "target-option" {
            post(61, true, .maskAlternate)
            post(61, false)
        } else {
            guard args.count >= 6, let code = UInt16(args[4]), let raw = UInt64(args[5]) else {
                fail("Invalid key")
            }
            let flags = CGEventFlags(rawValue: raw)
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
        }
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
