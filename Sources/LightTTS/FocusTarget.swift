import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import LightTTSRuntime

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private static func trace(_ message: @autoclosure () -> String) {
        if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE delivery %@", message()) }
    }
    private let pid: pid_t
    private let element: AXUIElement?
    private let window: AXUIElement?
    let shiftHeldAtStop: Bool
    private typealias ClipboardSnapshot = [[(NSPasteboard.PasteboardType, Data)]]
    private static let pasteLock = NSLock()
    private static let restoration = PasteRestoration<ClipboardSnapshot>()
    let stopDisposition: FocusDisposition
    private static let cacheLock = NSLock()
    private static var enabledPIDs: Set<pid_t> = []

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func focused(_ app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func isOpaque(_ app: NSRunningApplication?) -> Bool {
        let id = app?.bundleIdentifier?.lowercased() ?? ""
        let browsers = ["chrome", "chromium", "safari", "firefox", "edge", "brave", "arc", "opera", "vivaldi"]
        if browsers.contains(where: { id.contains($0) }) { return true }
        guard let url = app?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
    }
    private init(pid: pid_t, disposition: FocusDisposition, element: AXUIElement?, window: AXUIElement?, shiftHeld: Bool) {
        self.pid = pid; self.stopDisposition = disposition; self.element = element; self.window = window; self.shiftHeldAtStop = shiftHeld
    }
    static func capture(frontPID: pid_t?, shiftHeld: Bool = false) -> (target: FocusTarget?, secure: Bool) {
        let secure = IsSecureEventInputEnabled()
        guard let pid = frontPID else { return (nil, secure) }
        let running = NSRunningApplication(processIdentifier: pid)
        let opaque = isOpaque(running)
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
        if opaque {
            cacheLock.lock()
            if enabledPIDs.insert(pid).inserted {
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            }
            cacheLock.unlock()
        }
        let element = focused(app)
        let role = element.flatMap { attribute($0, kAXRoleAttribute) as? String }
        let subrole = element.flatMap { attribute($0, kAXSubroleAttribute) as? String }
        let disposition = focusDisposition(
            role: role, subrole: subrole,
            secureInput: secure, isOwnApp: pid == ProcessInfo.processInfo.processIdentifier || running?.bundleIdentifier == Bundle.main.bundleIdentifier,
            isFinder: running?.bundleIdentifier == "com.apple.finder", isOpaqueApp: opaque)
        let reason: String
        switch disposition {
        case .secure: reason = "secure input or field"
        case .unavailable: reason = "own app or Finder desktop"
        case .editable: reason = "editable role"
        case .uncertain: reason = "focus not conclusively classified"
        }
        trace("stop bundle=\(running?.bundleIdentifier ?? "nil") pid=\(pid) role=\(role ?? "nil") subrole=\(subrole ?? "nil") secureInput=\(secure) opaque=\(opaque) decision=\(disposition) reason=\(reason)")
        let window = focusedWindow(app)
        return (FocusTarget(pid: pid, disposition: disposition, element: element, window: window, shiftHeld: shiftHeld), secure)
    }
    private static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        guard let value = attribute(app, kAXFocusedWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func requireSafeFocus() throws {
        let front = NSWorkspace.shared.frontmostApplication
        Self.trace("focus-check bundle=\(front?.bundleIdentifier ?? "nil") pid=\(front?.processIdentifier ?? -1) expected=\(pid)")
        guard frontmostPID() == pid else { throw FocusError.changed }
        guard !IsSecureEventInputEnabled() else { throw FocusError.secure }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
        let currentElement = Self.focused(app)
        guard focusMatches(capturedElement: element, currentElement: currentElement, capturedWindow: window, currentWindow: Self.focusedWindow(app), equal: { CFEqual($0, $1) }) else { throw FocusError.changed }
        if let element = currentElement {
            let role = Self.attribute(element, kAXRoleAttribute) as? String
            let subrole = Self.attribute(element, kAXSubroleAttribute) as? String
            if role == "AXSecureTextField" || subrole == "AXSecureTextField" { throw FocusError.secure }
        }
    }
    private func frontmostPID() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    func sendReturn(isCurrent: () -> Bool = { true }) throws {
        guard isCurrent() else { throw FocusError.cancelled }
        try requireSafeFocus()
        guard isCurrent() else { throw FocusError.cancelled }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down); event?.flags = []; event?.post(tap: .cghidEventTap) }
    }
    func paste(_ text: String, restoreClipboard: Bool, allowClipboardHistory: Bool, isCurrent: () -> Bool = { true }) throws {
        try requireSafeFocus()
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        let deadline = ProcessInfo.processInfo.systemUptime + 2.0
        try waitForPasteModifiers(
            modifiersHeld: { !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty },
            isCurrent: isCurrent, timedOut: { ProcessInfo.processInfo.systemUptime >= deadline },
            pause: { Thread.sleep(forTimeInterval: 0.01) })
        try requireSafeFocus()
        let board = NSPasteboard.general
        guard isCurrent() else { throw FocusError.cancelled }
        Self.pasteLock.lock()
        let saved = Self.restoration.original(currentCount: board.changeCount) {
            (board.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            }
        }
        let item = transcriptPasteboardItem(text, allowClipboardHistory: allowClipboardHistory)
        board.clearContents(); board.writeObjects([item])
        let count = board.changeCount
        Self.restoration.published(count: count, original: saved, restore: restoreClipboard)
        Self.pasteLock.unlock()
        try requireSafeFocus()
        try verifyPasteOwnership(expected: count, current: { board.changeCount }, isCurrent: isCurrent)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw FocusError.eventCreationFailed }
        keyDown.flags = .maskCommand; keyUp.flags = .maskCommand
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        if restoreClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                Self.pasteLock.lock(); defer { Self.pasteLock.unlock() }
                guard let saved = Self.restoration.takeForRestore(expectedCount: count, currentCount: board.changeCount) else { return }
                let items = saved.map { values -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, data) in values { item.setData(data, forType: type) }
                    return item
                }
                board.clearContents()
                if !items.isEmpty { board.writeObjects(items) }
            }
        }
    }
}
