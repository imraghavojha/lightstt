import Foundation

public enum FocusDisposition: Sendable {
    case editable, uncertain, secure, unavailable
}
public enum FocusError: LocalizedError, Equatable {
    case secure, unavailable, changed, modifiersHeld, eventCreationFailed, clipboardChanged,
        cancelled
    public var errorDescription: String? {
        switch self {
        case .secure: return "Copied: secure field"
        case .unavailable: return "No focused editable field"
        case .changed: return "The focused field or app changed before text could be inserted"
        case .modifiersHeld: return "Release the shortcut keys before pasting"
        case .eventCreationFailed: return "Could not create paste keyboard events"
        case .clipboardChanged: return "The clipboard changed before pasting"
        case .cancelled: return "Delivery cancelled"
        }
    }
}

public func focusDisposition(
    role: String?, subrole: String?, secureInput: Bool, isOwnApp: Bool = false,
    isFinder: Bool = false, isOpaqueApp: Bool = false
) -> FocusDisposition {
    if secureInput || role == "AXSecureTextField" || subrole == "AXSecureTextField" {
        return .secure
    }
    if isOwnApp { return .unavailable }
    if let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) {
        return .editable
    }
    if isFinder { return .unavailable }
    let nonEditable = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXList", "AXTable", "AXOutline", "AXMenu",
        "AXMenuItem", "AXMenuBar", "AXStaticText", "AXImage", "AXSlider", "AXTabGroup",
    ]
    if !isOpaqueApp, let role, nonEditable.contains(role) { return .unavailable }
    return .uncertain
}

public func shouldRestoreClipboard(disposition: FocusDisposition, preference: Bool) -> Bool {
    return preference
}

public func typeInChunks(
    _ text: String, expectedPID: pid_t, currentPID: () -> pid_t?, post: (String) throws -> Void
) throws {
    var start = text.startIndex
    while start < text.endIndex {
        guard currentPID() == expectedPID else {
            throw FocusError.changed
        }
        let end = text.index(start, offsetBy: 32, limitedBy: text.endIndex) ?? text.endIndex
        try post(String(text[start..<end]))
        start = end
    }
}

public func performTextInput(
    _ text: String, simulateTyping: Bool, sendOnShift: Bool, shiftHeld: Bool,
    insert: (String) throws -> Void, type: (String) throws -> Void, sendReturn: () throws -> Void
) throws {
    if simulateTyping {
        try type(text)
    } else {
        try insert(text)
    }
    if sendOnShift && shiftHeld {
        try sendReturn()
    }
}

public func shouldCopyTranscript(autoPaste: Bool, restoreClipboard: Bool) -> Bool {
    !autoPaste || !restoreClipboard
}
