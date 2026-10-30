import ApplicationServices
import Foundation

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private let element: AXUIElement
    private let pid: pid_t
    private let window: AXUIElement?
    private let role: String?

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private static func windowOf(_ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func roleOf(_ element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute) as? String
    }
    private init?(_ element: AXUIElement, expectedPID: pid_t) {
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(element, &actualPID) == .success, actualPID == expectedPID else { return nil }
        self.element = element; self.pid = actualPID
        AXUIElementSetMessagingTimeout(element, 0.5)
        self.window = Self.windowOf(element); self.role = Self.roleOf(element)
    }
    static func capture(frontPID: pid_t?) -> FocusTarget? {
        let testPID = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TARGET_PID"].flatMap(Int32.init)
        guard let pid = testPID ?? frontPID else { return nil }
        let app = AXUIElementCreateApplication(pid); AXUIElementSetMessagingTimeout(app, 0.5)
        guard let value = attribute(app, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return FocusTarget(value as! AXUIElement, expectedPID: pid)
    }
    private func requireCurrentFocus() throws -> AXUIElement {
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system, 0.5)
        guard let value = Self.attribute(system, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { throw focusChanged() }
        let current = value as! AXUIElement
        AXUIElementSetMessagingTimeout(current, 0.5)
        var currentPID: pid_t = 0
        guard AXUIElementGetPid(current, &currentPID) == .success else { throw focusChanged() }
        let currentWindow = Self.windowOf(current)
        let sameWindow: Bool? = if let window, let currentWindow { CFEqual(window, currentWindow) } else { nil }
        guard focusTargetMatches(originalPID: pid, currentPID: currentPID,
                                 sameElement: CFEqual(element, current), sameWindow: sameWindow,
                                 originalRole: role, currentRole: Self.roleOf(current)) else { throw focusChanged() }
        return current
    }
    private func focusChanged() -> NSError {
        NSError(domain: "LightTTS.Accessibility", code: 1, userInfo: [NSLocalizedDescriptionKey: "The focused field changed before text could be inserted."])
    }
    func type(_ text: String) throws {
        _ = try requireCurrentFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            let units = Array(String(character).utf16)
            units.withUnsafeBufferPointer { buffer in
                for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down); event?.flags = []; event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress); event?.post(tap: .cghidEventTap) }
            }
        }
    }
    func sendReturn() throws {
        _ = try requireCurrentFocus()
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] { let event = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: down); event?.flags = []; event?.post(tap: .cghidEventTap) }
    }
    func insert(_ text: String) throws {
        let current = try requireCurrentFocus()
        let result = AXUIElementSetAttributeValue(current, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard result == .success else { throw NSError(domain: "LightTTS.Accessibility", code: Int(result.rawValue), userInfo: [NSLocalizedDescriptionKey: "Could not insert into the focused field (Accessibility error \(result.rawValue))."]) }
    }
}
