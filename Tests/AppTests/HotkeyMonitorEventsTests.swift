import AppKit
import XCTest

@testable import LightTTS

/// The global input monitor must stay installed for every shortcut that needs it.
@MainActor final class HotkeyMonitorEventsTests: XCTestCase {
    private let optionSpace = Shortcut(code: 49, flags: .option)
    private let escape = Shortcut(code: 53, flags: [])
    private let rightOption = Shortcut(code: 61, flags: [])

    private func events(_ shortcuts: [UInt32: Shortcut], mouse: Int = -1) -> NSEvent.EventTypeMask {
        let monitor = HotkeyMonitor()
        monitor.configuredShortcuts = shortcuts
        monitor.configuredMouseButton = mouse
        return monitor.monitoredEvents
    }

    func testKeyCombinationsNeedNoGlobalMonitor() {
        XCTAssertEqual(events([1: optionSpace, 3: escape]), [])
        let push = Shortcut(code: 49, flags: [.option, .shift])
        XCTAssertEqual(events([1: optionSpace, 2: push, 3: escape]), [])
    }

    func testModifierOnlyToggleWatchesFlagsAndKeys() {
        XCTAssertEqual(events([1: rightOption, 3: escape]), [.flagsChanged, .keyDown])
    }

    func testModifierOnlyPushToTalkWatchesFlags() {
        XCTAssertEqual(events([1: optionSpace, 2: rightOption, 3: escape]), [.flagsChanged])
    }

    func testModifierOnlyCancelWatchesFlags() {
        XCTAssertEqual(events([1: optionSpace, 3: Shortcut(code: 59, flags: [])]), [.flagsChanged])
    }

    func testMouseShortcutWatchesOtherMouseButtons() {
        XCTAssertEqual(
            events([1: optionSpace, 3: escape], mouse: 3), [.otherMouseDown, .otherMouseUp])
    }
}
