import AppKit
import XCTest
@testable import LightTTS

@MainActor final class ShortcutCaptureLifecycleTests: XCTestCase {
    func testRemovingKeyboardRecorderEndsCapture() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let button = ShortcutButton(
            codeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", fallbackCode: 49,
            enabledKey: nil)
        window.contentView!.addSubview(button)
        button.performClick(nil)
        XCTAssertTrue(ShortcutButton.isRecording)
        button.removeFromSuperview()
        XCTAssertFalse(ShortcutButton.isRecording)
    }

    func testRemovingMouseRecorderEndsCapture() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        let button = MouseShortcutButton()
        window.contentView!.addSubview(button)
        button.performClick(nil)
        XCTAssertTrue(MouseShortcutButton.isRecording)
        button.removeFromSuperview()
        XCTAssertFalse(MouseShortcutButton.isRecording)
    }
}
