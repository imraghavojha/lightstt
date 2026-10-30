import XCTest
@testable import LightTTSCore

final class ToggleShortcutStateTests: XCTestCase {
    func testKeyPressReleaseRepeatAndSecondPress() {
        var state = ToggleShortcutState()
        XCTAssertTrue(state.key(true))
        XCTAssertFalse(state.key(true)) // auto-repeat
        XCTAssertFalse(state.key(false))
        XCTAssertTrue(state.key(true))
        XCTAssertFalse(state.key(false))
    }

    func testModifierTapAndChord() {
        var state = ToggleShortcutState()
        XCTAssertFalse(state.modifier(true))
        XCTAssertTrue(state.modifier(false))
        XCTAssertFalse(state.modifier(false))
        XCTAssertFalse(state.modifier(true))
        state.usedInChord()
        XCTAssertFalse(state.modifier(false))
        XCTAssertFalse(state.modifier(true))
        XCTAssertTrue(state.modifier(false))
    }

    func testResetDiscardsPendingModifierTap() {
        var state = ToggleShortcutState()
        XCTAssertFalse(state.modifier(true))
        state.reset()
        XCTAssertFalse(state.modifier(false))
    }
    func testLostReleasesAreDiscardedOnResynchronization() {
        var state = ToggleShortcutState()
        XCTAssertTrue(state.key(true))
        state.reset() // Workspace activation, wake, or unlock.
        XCTAssertTrue(state.key(true))

        state.reset()
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0x40))
        state.usedInChord()
        // An unrelated flags event observes the missed release.
        XCTAssertFalse(state.flagsChanged(code: 57, shortcutCode: 61, eventFlags: 0, currentFlags: 0))
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0x40))
        XCTAssertTrue(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0, currentFlags: 0))
    }

    func testCapsLockAndFnDoNotMakeAChord() {
        for noise in [57, 63] {
            var state = ToggleShortcutState()
            XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0x40))
            XCTAssertFalse(state.flagsChanged(code: noise, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0x40))
            XCTAssertTrue(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0, currentFlags: 0))
        }
    }

    func testOtherModifiersAreChordsAndPhysicalSidesStayDistinct() {
        var state = ToggleShortcutState()
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0x40))
        XCTAssertFalse(state.flagsChanged(code: 58, shortcutCode: 61, eventFlags: 0x60, currentFlags: 0x60))
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x20, currentFlags: 0x20))
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0x40, currentFlags: 0))
        XCTAssertFalse(state.flagsChanged(code: 61, shortcutCode: 61, eventFlags: 0, currentFlags: 0))
    }

}
