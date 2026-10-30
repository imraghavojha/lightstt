import Foundation

func performTextInput(_ text: String, simulateTyping: Bool, sendOnShift: Bool, shiftHeld: Bool, insert: (String) throws -> Void, type: (String) throws -> Void, sendReturn: () throws -> Void) throws {
    if simulateTyping { try type(text) } else { try insert(text) }
    if sendOnShift && shiftHeld { try sendReturn() }
}

func shouldCopyTranscript(autoPaste: Bool, restoreClipboard: Bool) -> Bool {
    !autoPaste || !restoreClipboard
}
