import Foundation

func performTextInput(_ text: String, simulateTyping: Bool, sendOnShift: Bool, shiftHeld: Bool, insert: (String) throws -> Void, type: (String) throws -> Void, sendReturn: () throws -> Void) throws {
    if simulateTyping { try type(text) } else { try insert(text) }
    if sendOnShift && shiftHeld { try sendReturn() }
}

func shouldCopyTranscript(autoPaste: Bool, restoreClipboard: Bool) -> Bool {
    !autoPaste || !restoreClipboard
}

// Unknown windows or roles cannot establish that a replacement element is safe.
func focusTargetMatches(originalPID: pid_t, currentPID: pid_t, sameElement: Bool, sameWindow: Bool?, originalRole: String?, currentRole: String?) -> Bool {
    guard originalPID == currentPID, sameWindow != false else { return false }
    return sameElement || (sameWindow == true && originalRole != nil && originalRole == currentRole)
}
