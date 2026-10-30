import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation
import LightTTSRuntime

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private let pid: pid_t
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
    private init(pid: pid_t, disposition: FocusDisposition) {
        self.pid = pid; self.stopDisposition = disposition
    }
    static func capture(frontPID: pid_t?) -> (target: FocusTarget?, secure: Bool) {
        let secure = IsSecureEventInputEnabled()
        let testPID = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"].flatMap(Int32.init)
        guard let pid = testPID ?? frontPID else { return (nil, secure) }
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
        let disposition = focusDisposition(
            role: element.flatMap { attribute($0, kAXRoleAttribute) as? String },
            subrole: element.flatMap { attribute($0, kAXSubroleAttribute) as? String },
            secureInput: secure, isOwnApp: pid == ProcessInfo.processInfo.processIdentifier || running?.bundleIdentifier == Bundle.main.bundleIdentifier,
            isFinder: running?.bundleIdentifier == "com.apple.finder", isOpaqueApp: opaque)
        return (FocusTarget(pid: pid, disposition: disposition), secure)
    }
    private func requireSafeFocus() throws {
        guard frontmostPID() == pid else { throw FocusError.changed }
        guard !IsSecureEventInputEnabled() else { throw FocusError.secure }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
        if let element = Self.focused(app) {
            let role = Self.attribute(element, kAXRoleAttribute) as? String
            let subrole = Self.attribute(element, kAXSubroleAttribute) as? String
            if role == "AXSecureTextField" || subrole == "AXSecureTextField" { throw FocusError.secure }
        }
    }
    private func frontmostPID() -> pid_t? {
        ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"].flatMap(Int32.init) ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    func sendReturn() throws {
        try requireSafeFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down); event?.flags = []; event?.post(tap: .cghidEventTap) }
    }
    func paste(_ text: String, restoreClipboard: Bool, allowClipboardHistory: Bool) throws {
        try requireSafeFocus()
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        let item = transcriptPasteboardItem(text, allowClipboardHistory: allowClipboardHistory)
        board.clearContents(); board.writeObjects([item])
        let count = board.changeCount
        let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
        let deadline = ProcessInfo.processInfo.systemUptime + 2.0
        while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw FocusError.modifiersHeld }
            Thread.sleep(forTimeInterval: min(0.01, max(0, deadline - ProcessInfo.processInfo.systemUptime)))
        }
        try requireSafeFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { throw FocusError.eventCreationFailed }
        keyDown.flags = .maskCommand; keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap); keyUp.post(tap: .cghidEventTap)
        if restoreClipboard {
            Thread.sleep(forTimeInterval: 0.4)
            if board.changeCount == count {
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
