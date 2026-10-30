import Foundation

var calls: [String] = []
func check(_ typing: Bool, _ send: Bool, _ shift: Bool, _ expected: [String]) throws {
    calls = []
    try performTextInput("hello", simulateTyping: typing, sendOnShift: send, shiftHeld: shift, insert: { calls.append("insert:" + $0) }, type: { calls.append("type:" + $0) }, sendReturn: { calls.append("return") })
    precondition(calls == expected)
}
try check(false, true, true, ["insert:hello", "return"])
try check(true, true, false, ["type:hello"])
try check(true, false, true, ["type:hello"])
precondition(!shouldCopyTranscript(autoPaste: true, restoreClipboard: true))
precondition(shouldCopyTranscript(autoPaste: true, restoreClipboard: false))
precondition(shouldCopyTranscript(autoPaste: false, restoreClipboard: true))
print("text input policy checks passed")
