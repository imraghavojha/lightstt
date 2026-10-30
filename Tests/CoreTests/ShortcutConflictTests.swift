import XCTest
@testable import LightTTSCore

final class ShortcutConflictTests: XCTestCase {
    func testShortcutConflicts() {
        XCTAssertTrue(ShortcutConflict.matches(code: 49, modifiers: 1, modifierOnly: false, otherCode: 49, otherModifiers: 1))
        XCTAssertFalse(ShortcutConflict.matches(code: 49, modifiers: 1, modifierOnly: false, otherCode: 49, otherModifiers: 2))
        XCTAssertFalse(ShortcutConflict.matches(code: 49, modifiers: 1, modifierOnly: false, otherCode: 53, otherModifiers: 1))
        XCTAssertTrue(ShortcutConflict.matches(code: 61, modifiers: 0, modifierOnly: true, otherCode: 61, otherModifiers: 2))
    }
}
