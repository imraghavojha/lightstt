import Foundation
import XCTest
@testable import LightTTSRuntime

private final class FakeTarget: TextTarget, @unchecked Sendable {
    var calls: [String] = []
    var error: FocusError?
    func insert(_ text: String) throws { try record("insert: \(text)") }
    func type(_ text: String) throws { try record("type: \(text)") }
    func sendReturn() throws { try record("return") }
    private func record(_ call: String) throws {
        calls.append(call)
        if let error { throw error }
    }
}

@MainActor
private final class FakeClipboard: TranscriptClipboard {
    var writes: [(String, Bool)] = []
    func write(_ text: String, allowClipboardHistory: Bool) {
        writes.append((text, allowClipboardHistory))
    }
}

@MainActor
private struct FakeFocus: FocusCapturing {
    let ticket: FocusTicket
    func captureAtStop() -> FocusTicket { ticket }
}

@MainActor
final class InsertionServiceTests: XCTestCase {
    private func makeService(
        result: FocusResult, clipboard: FakeClipboard, typing: Bool = false,
        send: Bool = false, shift: Bool = false, restore: Bool = true,
        history: Bool = true, accessible: Bool = true
    ) -> InsertionService {
        let ticket = FocusTicket { result }
        return InsertionService(
            focus: FakeFocus(ticket: ticket), clipboard: clipboard,
            options: {
                InsertionOptions(
                    simulateTyping: typing, sendOnShift: send, restoreClipboard: restore,
                    allowClipboardHistory: history)
            }, accessibilityGranted: { accessible }, shiftHeld: { shift })
    }

    func testClipboardWhenAutoPasteDisabledAndHistoryFlag() async {
        let clipboard = FakeClipboard()
        let service = makeService(
            result: FocusResult(target: nil, disposition: .unavailable), clipboard: clipboard,
            history: false)
        let outcome = await service.deliver("hello", to: service.captureAtStop(), autoPaste: false)
        { true }
        XCTAssertEqual(outcome, InsertionOutcome(delivery: .copied))
        XCTAssertEqual(clipboard.writes.count, 1)
        XCTAssertEqual(clipboard.writes.first?.0, "hello")
        XCTAssertEqual(clipboard.writes.first?.1, false)
    }

    func testWarningsCopyForAccessibilitySecureAndUnavailable() async {
        let cases: [(FocusDisposition, Bool, String)] = [
            (
                .editable, false,
                "Grant Accessibility to auto-paste. The transcription was copied to the clipboard."
            ),
            (.secure, true, "Copied: secure field"),
            (
                .unavailable, true,
                "No focused editable field. The transcription was copied to the clipboard."
            ),
        ]
        for (disposition, accessible, warning) in cases {
            let clipboard = FakeClipboard()
            let target = FakeTarget()
            let service = makeService(
                result: FocusResult(target: target, disposition: disposition), clipboard: clipboard,
                accessible: accessible)
            let outcome = await service.deliver(
                "hello", to: service.captureAtStop(), autoPaste: true
            ) { true }
            XCTAssertEqual(outcome, InsertionOutcome(delivery: .copied, warning: warning))
            XCTAssertEqual(clipboard.writes.count, 1)
            XCTAssertTrue(target.calls.isEmpty)
        }
    }

    func testMissingTargetAndChangedTargetCopy() async {
        let clipboard = FakeClipboard()
        let missing = makeService(
            result: FocusResult(target: nil, disposition: .editable), clipboard: clipboard)
        let missingOutcome = await missing.deliver(
            "hello", to: missing.captureAtStop(), autoPaste: true
        ) { true }
        XCTAssertEqual(
            missingOutcome.warning,
            "No focused editable field. The transcription was copied to the clipboard.")
        let target = FakeTarget()
        target.error = .changed
        let changed = makeService(
            result: FocusResult(target: target, disposition: .editable), clipboard: clipboard)
        let changedOutcome = await changed.deliver(
            "hello", to: changed.captureAtStop(), autoPaste: true
        ) { true }
        XCTAssertEqual(changedOutcome.delivery, .copied)
        XCTAssertEqual(
            changedOutcome.warning,
            "Could not auto-paste: The focused field or app changed before text could be inserted. The transcription was copied to the clipboard."
        )
        XCTAssertEqual(clipboard.writes.count, 2)
    }

    func testInsertionTypingReturnAndClipboardPreference() async {
        for typing in [false, true] {
            let target = FakeTarget()
            let clipboard = FakeClipboard()
            let service = makeService(
                result: FocusResult(target: target, disposition: .editable), clipboard: clipboard,
                typing: typing, send: true, shift: true, restore: typing)
            let outcome = await service.deliver(
                "hello", to: service.captureAtStop(), autoPaste: true
            ) { true }
            XCTAssertEqual(outcome, InsertionOutcome(delivery: .delivered))
            XCTAssertEqual(target.calls, [typing ? "type: hello" : "insert: hello", "return"])
            XCTAssertEqual(clipboard.writes.count, typing ? 0 : 1)
        }
    }

    func testNoReturnWithoutShiftAndSecureErrorCopies() async {
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        let service = makeService(
            result: FocusResult(target: target, disposition: .editable), clipboard: clipboard,
            send: true)
        _ = await service.deliver("hello", to: service.captureAtStop(), autoPaste: true) { true }
        XCTAssertEqual(target.calls, ["insert: hello"])
        target.error = .secure
        let outcome = await service.deliver("hello", to: service.captureAtStop(), autoPaste: true) {
            true
        }
        XCTAssertEqual(
            outcome, InsertionOutcome(delivery: .copied, warning: "Copied: secure field"))
    }

    func testStaleBeforeDeliveryAndAfterFocusResolution() async {
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        var current = true
        let ticket = FocusTicket {
            current = false
            return FocusResult(target: target, disposition: .editable)
        }
        let service = makeService(
            result: FocusResult(target: target, disposition: .editable), clipboard: clipboard)
        let stale = await service.deliver("hello", to: ticket, autoPaste: true) { current }
        XCTAssertEqual(stale.delivery, .skipped)
        let disabled = await service.deliver("hello", to: ticket, autoPaste: false) { false }
        XCTAssertEqual(disabled.delivery, .skipped)
        XCTAssertTrue(target.calls.isEmpty)
        XCTAssertTrue(clipboard.writes.isEmpty)
    }
}
