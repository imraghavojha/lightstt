import Foundation

public func focusMatches<Element>(
    capturedElement: Element?, currentElement: Element?, capturedWindow: Element?,
    currentWindow: Element?, equal: (Element, Element) -> Bool
) -> Bool {
    func matches(_ captured: Element?, _ current: Element?) -> Bool {
        guard let captured else { return true }
        guard let current else { return false }
        return equal(captured, current)
    }
    return matches(capturedElement, currentElement) && matches(capturedWindow, currentWindow)
}

public func waitForPasteModifiers(
    modifiersHeld: () -> Bool, isCurrent: () -> Bool, timedOut: () -> Bool,
    pause: () -> Void
) throws {
    while modifiersHeld() {
        guard isCurrent() else { throw FocusError.cancelled }
        guard !timedOut() else { throw FocusError.modifiersHeld }
        pause()
    }
    guard isCurrent() else { throw FocusError.cancelled }
}

public func verifyPasteOwnership(expected: Int, current: () -> Int, isCurrent: () -> Bool) throws {
    guard isCurrent() else { throw FocusError.cancelled }
    guard current() == expected else { throw FocusError.clipboardChanged }
}
