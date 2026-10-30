import Foundation

enum FocusDisposition { case editable, secure, unavailable }
enum FocusError: LocalizedError {
    case secure, unavailable, changed
    var errorDescription: String? {
        switch self {
        case .secure: return "Copied: secure field"
        case .unavailable: return "No focused editable field"
        case .changed: return "The focused field or app changed before text could be inserted"
        }
    }
}

func focusDisposition(role: String?, subrole: String?, secureInput: Bool) -> FocusDisposition {
    if secureInput || role == "AXSecureTextField" || subrole == "AXSecureTextField" { return .secure }
    guard let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) else { return .unavailable }
    return .editable
}

func typeInChunks(_ text: String, expectedPID: pid_t, currentPID: () -> pid_t?, post: (String) throws -> Void) throws {
    var start = text.startIndex
    while start < text.endIndex {
        guard currentPID() == expectedPID else { throw FocusError.changed }
        let end = text.index(start, offsetBy: 32, limitedBy: text.endIndex) ?? text.endIndex
        try post(String(text[start..<end]))
        start = end
    }
}

func performTextInput(_ text: String, simulateTyping: Bool, sendOnShift: Bool, shiftHeld: Bool, insert: (String) throws -> Void, type: (String) throws -> Void, sendReturn: () throws -> Void) throws {
    if simulateTyping { try type(text) } else { try insert(text) }
    if sendOnShift && shiftHeld { try sendReturn() }
}

func shouldCopyTranscript(autoPaste: Bool, restoreClipboard: Bool) -> Bool {
    !autoPaste || !restoreClipboard
}
