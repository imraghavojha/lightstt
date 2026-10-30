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
}
