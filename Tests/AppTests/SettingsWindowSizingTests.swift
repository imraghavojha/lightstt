import AppKit
import XCTest
@testable import LightTTS

final class SettingsWindowSizingTests: XCTestCase {
    func testResizeEnforcesEachMinimumDimension() {
        XCTAssertEqual(
            SettingsWindowSizing.clamped(NSSize(width: 400, height: 300)),
            NSSize(width: 750, height: 508))
        XCTAssertEqual(
            SettingsWindowSizing.clamped(NSSize(width: 1000, height: 300)),
            NSSize(width: 1000, height: 508))
        XCTAssertEqual(
            SettingsWindowSizing.clamped(NSSize(width: 400, height: 800)),
            NSSize(width: 750, height: 800))
        XCTAssertEqual(
            SettingsWindowSizing.clamped(NSSize(width: 1000, height: 800)),
            NSSize(width: 1000, height: 800))
    }
}
