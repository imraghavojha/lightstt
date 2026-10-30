import ApplicationServices
import Foundation

/// Accessibility calls are bounded and performed away from the UI/event-tap thread.
final class FocusTarget: @unchecked Sendable {
    private let element: AXUIElement
    private init(_ element: AXUIElement) { self.element = element; AXUIElementSetMessagingTimeout(element, 0.5) }
    static func capture(frontPID: pid_t?) -> FocusTarget? {
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
    func insert(_ text: String) throws {
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard result == .success else { throw NSError(domain: "LightTTS.Accessibility", code: Int(result.rawValue), userInfo: [NSLocalizedDescriptionKey: "Could not insert into the focused field (Accessibility error \(result.rawValue))."]) }
    }
}
