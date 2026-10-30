import ApplicationServices
import Foundation

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private let element: AXUIElement
    private init(_ element: AXUIElement) { self.element = element; AXUIElementSetMessagingTimeout(element, 0.5) }
    static func capture(frontPID: pid_t?) -> FocusTarget? {
        if let value = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"], let pid = Int32(value) {
            let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused { return FocusTarget(focused as! AXUIElement) }
            return nil
        }
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.5)
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value { return FocusTarget(value as! AXUIElement) }
        if let frontPID {
            let app = AXUIElementCreateApplication(frontPID); AXUIElementSetMessagingTimeout(app, 0.5)
            value = nil
            if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value { return FocusTarget(value as! AXUIElement) }
        }
        return nil
    }
    private func requireCurrentFocus() throws {
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success, let value, CFEqual(element, value) else { throw NSError(domain: "LightTTS.Accessibility", code: 1, userInfo: [NSLocalizedDescriptionKey: "The focused field changed before text could be inserted."]) }
    }
    func type(_ text: String) throws {
        try requireCurrentFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            units.withUnsafeBufferPointer { buffer in
                for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down); event?.flags = []; event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress); event?.post(tap: .cghidEventTap) }
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
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard result == .success else { throw NSError(domain: "LightTTS.Accessibility", code: Int(result.rawValue), userInfo: [NSLocalizedDescriptionKey: "Could not insert into the focused field (Accessibility error \(result.rawValue))."]) }
    }
}
