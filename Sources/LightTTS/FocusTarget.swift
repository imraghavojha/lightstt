import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private let element: AXUIElement?
    private let pid: pid_t
    private let stopDisposition: FocusDisposition

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func disposition(_ element: AXUIElement) -> FocusDisposition {
        var settable = DarwinBoolean(false)
        let rangeSettable = AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success && settable.boolValue
        return focusDisposition(role: attribute(element, kAXRoleAttribute) as? String,
                         subrole: attribute(element, kAXSubroleAttribute) as? String,
                         secureInput: IsSecureEventInputEnabled(),
                         editable: (attribute(element, "AXEditable") as? Bool) == true, selectedRangeSettable: rangeSettable)
    }
    private init?(_ element: AXUIElement, expectedPID: pid_t) {
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(element, &actualPID) == .success, actualPID == expectedPID else { return nil }
        self.element = element; self.pid = actualPID
        AXUIElementSetMessagingTimeout(element, 0.5)
        self.stopDisposition = Self.disposition(element)
    }
    private init(missingPID: pid_t) {
        element = nil; pid = missingPID; stopDisposition = .editable
    }
    static func capture(frontPID: pid_t?) -> (target: FocusTarget?, secure: Bool) {
        let secure = IsSecureEventInputEnabled()
        let testPID = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"].flatMap(Int32.init)
        guard let pid = testPID ?? frontPID else { return (nil, secure) }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
        if let running = NSRunningApplication(processIdentifier: pid), let url = running.bundleURL {
            let id = running.bundleIdentifier?.lowercased() ?? ""
            let chromium = ["chrome", "chromium", "brave", "edge", "vivaldi", "opera"].contains { id.contains($0) }
            let electron = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
            if chromium || electron {
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
        }
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            guard !secure, NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { return (nil, secure) }
            return (FocusTarget(missingPID: pid), false)
        }
        return (FocusTarget(value as! AXUIElement, expectedPID: pid), secure)
    }
    private func requireCurrentFocus() throws {
        try checkDisposition(stopDisposition)
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.5)
        guard !IsSecureEventInputEnabled() else { throw FocusError.secure }
        guard frontmostPID() == pid else { throw FocusError.changed }
        guard let value = Self.attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            if element == nil { return }
            throw FocusError.unavailable
        }
        let current = value as! AXUIElement
        AXUIElementSetMessagingTimeout(current, 0.5)
        let currentDisposition = Self.disposition(current)
        if currentDisposition == .secure { throw FocusError.secure }
        if element != nil { try checkDisposition(currentDisposition) }
        var currentPID: pid_t = 0
        guard AXUIElementGetPid(current, &currentPID) == .success, currentPID == pid else { throw FocusError.changed }
        if let element, !CFEqual(element, current) { throw FocusError.changed }
    }
    private func checkDisposition(_ disposition: FocusDisposition) throws {
        switch disposition {
        case .secure: throw FocusError.secure
        case .unavailable: throw FocusError.unavailable
        case .editable: break
        }
    }
    private func frontmostPID() -> pid_t? {
        ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"].flatMap(Int32.init) ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
    func type(_ text: String) throws {
        if element == nil { try paste(text); return }
        try requireCurrentFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        try typeInChunks(text, expectedPID: pid, currentPID: frontmostPID) { chunk in
            // Recheck security as well as the app before posting each chunk.
            try self.requireCurrentFocus()
            for character in chunk {
                let units = Array(String(character).utf16)
                units.withUnsafeBufferPointer { buffer in
                    for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down); event?.flags = []; event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress); event?.post(tap: .cghidEventTap) }
                }
            }
        }
    }
    func sendReturn() throws {
        try requireCurrentFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down); event?.flags = []; event?.post(tap: .cghidEventTap) }
    }
    func insert(_ text: String) throws {
        try requireCurrentFocus()
        guard let element else { try paste(text); return }
        let before = Self.attribute(element, kAXValueAttribute) as? String
        let selected = Self.attribute(element, kAXSelectedTextAttribute) as? String
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        if result != .success { try paste(text); return }
        if let before, let after = Self.attribute(element, kAXValueAttribute) as? String, before == after, selected != text {
            try paste(text)
        }
    }
    private func paste(_ text: String) throws {
        try requireCurrentFocus()
        let board = NSPasteboard.general
        let saved = (board.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        writeTranscriptToClipboard(text)
        let count = board.changeCount
        do {
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate, .maskSecondaryFn]
            let deadline = ProcessInfo.processInfo.systemUptime + 2.0
            while !CGEventSource.flagsState(.combinedSessionState).intersection(modifiers).isEmpty {
                guard ProcessInfo.processInfo.systemUptime < deadline else { throw FocusError.modifiersHeld }
                Thread.sleep(forTimeInterval: min(0.01, max(0, deadline - ProcessInfo.processInfo.systemUptime)))
            }
            try requireCurrentFocus()
            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                throw FocusError.eventCreationFailed
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        } catch {
            // The caller leaves the transcript on the clipboard when delivery fails.
            throw error
        }
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
