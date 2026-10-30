import AppKit
import Foundation
import XCTest
@testable import LightTTSRuntime

private final class FakeTarget: TextTarget, @unchecked Sendable {
    var calls: [String] = []
    var error: FocusError?
    var ranOnMainThread: Bool?
    var restores: [Bool] = []
    func paste(
        _ text: String, restoreClipboard: Bool, allowClipboardHistory: Bool, isCurrent: () -> Bool
    ) throws {
        restores.append(restoreClipboard)
        try record("paste: \(text)")
    }
    func sendReturn(isCurrent: () -> Bool) throws { try record("return") }
    private func record(_ call: String) throws {
        ranOnMainThread = Thread.isMainThread
        calls.append(call)
        if let error { throw error }
    }
}

@MainActor
private final class FakeClipboard: TranscriptClipboard {
    var writes: [(String, Bool)] = []
    var recordedTypes: [[NSPasteboard.PasteboardType]] = []
    func write(_ text: String, allowClipboardHistory: Bool) {
        writes.append((text, allowClipboardHistory))
        recordedTypes.append(
            transcriptPasteboardItem(text, allowClipboardHistory: allowClipboardHistory).types)
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

    func testAccessibilityWarningAndQuietCopies() async {
        let cases: [(FocusDisposition, Bool, String?)] = [
            (
                .editable, false,
                "Grant Accessibility to auto-paste. The transcription was copied to the clipboard."
            ),
            (.secure, true, nil),
            (.unavailable, true, nil),
        ]
        for (disposition, accessible, warning) in cases {
            for history in [false, true] {
                let clipboard = FakeClipboard()
                let target = FakeTarget()
                let service = makeService(
                    result: FocusResult(target: target, disposition: disposition),
                    clipboard: clipboard,
                    history: history, accessible: accessible)
                let outcome = await service.deliver(
                    "hello", to: service.captureAtStop(), autoPaste: true
                ) { true }
                XCTAssertEqual(outcome, InsertionOutcome(delivery: .copied, warning: warning))
                XCTAssertEqual(clipboard.writes.count, 1)
                XCTAssertEqual(clipboard.writes.first?.1, history)
                XCTAssertTrue(target.calls.isEmpty)
            }
        }
    }

    func testMissingTargetAndChangedTargetCopy() async {
        let clipboard = FakeClipboard()
        let missing = makeService(
            result: FocusResult(target: nil, disposition: .editable), clipboard: clipboard)
        let missingOutcome = await missing.deliver(
            "hello", to: missing.captureAtStop(), autoPaste: true
        ) { true }
        XCTAssertEqual(missingOutcome, InsertionOutcome(delivery: .copied))
        let target = FakeTarget()
        target.error = .changed
        let changed = makeService(
            result: FocusResult(target: target, disposition: .editable), clipboard: clipboard)
        let changedOutcome = await changed.deliver(
            "hello", to: changed.captureAtStop(), autoPaste: true
        ) { true }
        XCTAssertEqual(changedOutcome.delivery, .copied)
        XCTAssertNil(changedOutcome.warning)
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
            XCTAssertEqual(target.calls, ["paste: hello", "return"])
            XCTAssertEqual(target.ranOnMainThread, false)
            XCTAssertTrue(clipboard.writes.isEmpty)
            XCTAssertEqual(target.restores, [typing])
        }
    }

    func testNoReturnWithoutShiftAndSecureErrorCopies() async {
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        let service = makeService(
            result: FocusResult(target: target, disposition: .editable), clipboard: clipboard,
            send: true)
        _ = await service.deliver("hello", to: service.captureAtStop(), autoPaste: true) { true }
        XCTAssertEqual(target.calls, ["paste: hello"])
        target.error = .secure
        let outcome = await service.deliver("hello", to: service.captureAtStop(), autoPaste: true) {
            true
        }
        XCTAssertEqual(
            outcome, InsertionOutcome(delivery: .copied))
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
    func testStaleInsideWorkerAndAfterInsertion() async {
        for staleCheck in [3, 4] {
            let target = FakeTarget()
            let clipboard = FakeClipboard()
            let service = makeService(
                result: FocusResult(target: target, disposition: .editable), clipboard: clipboard,
                restore: false)
            var checks = 0
            let outcome = await service.deliver(
                "hello", to: service.captureAtStop(), autoPaste: true
            ) {
                checks += 1
                return checks != staleCheck
            }
            XCTAssertEqual(outcome.delivery, .skipped)
            XCTAssertEqual(checks, staleCheck)
            XCTAssertEqual(target.calls, staleCheck == 3 ? [] : ["paste: hello"])
            XCTAssertTrue(clipboard.writes.isEmpty)
        }
    }

    func testClipboardPreferencesAreReadAfterInsertion() async {
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        var restore = true
        var history = true
        let service = InsertionService(
            focus: FakeFocus(
                ticket: FocusTicket {
                    FocusResult(target: target, disposition: .editable)
                }), clipboard: clipboard,
            options: {
                InsertionOptions(
                    simulateTyping: false, sendOnShift: false, restoreClipboard: restore,
                    allowClipboardHistory: history)
            }, accessibilityGranted: { true }, shiftHeld: { false })
        var checks = 0
        let outcome = await service.deliver(
            "hello", to: service.captureAtStop(), autoPaste: true
        ) {
            checks += 1
            if checks == 4 {
                restore = false
                history = false
            }
            return true
        }
        XCTAssertEqual(outcome.delivery, .delivered)
        XCTAssertTrue(clipboard.writes.isEmpty)
        XCTAssertEqual(target.calls, ["paste: hello"])
    }

    func testFocusPolicyAndRestoration() async {
        XCTAssertEqual(
            focusDisposition(role: nil, subrole: nil, secureInput: false, isOpaqueApp: true),
            .uncertain)
        XCTAssertEqual(
            focusDisposition(role: "AXButton", subrole: nil, secureInput: false, isOpaqueApp: true),
            .uncertain)
        XCTAssertEqual(
            focusDisposition(role: nil, subrole: nil, secureInput: false, isFinder: true),
            .unavailable)
        XCTAssertEqual(
            focusDisposition(role: "AXTextField", subrole: nil, secureInput: false, isOwnApp: true),
            .unavailable)
        XCTAssertEqual(
            focusDisposition(role: "AXTextField", subrole: "AXSecureTextField", secureInput: false),
            .secure)
        XCTAssertTrue(shouldRestoreClipboard(disposition: .uncertain, preference: true))
        XCTAssertFalse(shouldRestoreClipboard(disposition: .editable, preference: false))
        XCTAssertTrue(shouldRestoreClipboard(disposition: .editable, preference: true))
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        let service = makeService(
            result: FocusResult(target: target, disposition: .uncertain), clipboard: clipboard)
        let outcome = await service.deliver("hello", to: service.captureAtStop(), autoPaste: true) {
            true
        }
        XCTAssertEqual(outcome.delivery, .delivered)
        XCTAssertEqual(target.calls, ["paste: hello"])
        XCTAssertEqual(target.restores, [true])
    }

    func testClipboardMarkerTypes() async {
        let clipboard = FakeClipboard()
        let service = makeService(
            result: FocusResult(target: nil, disposition: .unavailable), clipboard: clipboard,
            history: false)
        _ = await service.deliver("private", to: service.captureAtStop(), autoPaste: false) { true }
        let types = Set(clipboard.recordedTypes[0].map(\.rawValue))
        XCTAssertEqual(
            types,
            [
                NSPasteboard.PasteboardType.string.rawValue, "org.nspasteboard.TransientType",
                "org.nspasteboard.ConcealedType",
            ])
        clipboard.write("public", allowClipboardHistory: true)
        XCTAssertEqual(clipboard.recordedTypes[1], [.string])
    }

    func testNativeNonEditableControlsAndOpaqueEditors() {
        for role in ["AXButton", "AXList", "AXTable", "AXMenu", "AXStaticText"] {
            XCTAssertEqual(
                focusDisposition(role: role, subrole: nil, secureInput: false), .unavailable)
            XCTAssertEqual(
                focusDisposition(role: role, subrole: nil, secureInput: false, isOpaqueApp: true),
                .uncertain)
        }
    }

    func testOverlappingRestorationsCarryOriginalAndRespectExternalChange() {
        let restore = PasteRestoration<String>()
        let original = restore.original(currentCount: 1) { "original" }
        restore.published(count: 2, original: original, restore: true)
        let carried = restore.original(currentCount: 2) { "first transcript" }
        restore.published(count: 3, original: carried, restore: true)
        XCTAssertNil(restore.takeForRestore(expectedCount: 2, currentCount: 3))
        XCTAssertEqual(restore.takeForRestore(expectedCount: 3, currentCount: 3), "original")
        restore.published(count: 4, original: original, restore: true)
        XCTAssertNil(restore.takeForRestore(expectedCount: 4, currentCount: 5))
    }

    func testStopFocusIdentityAndOpaqueFallback() {
        XCTAssertTrue(
            focusMatches(
                capturedElement: 1, currentElement: 1, capturedWindow: 2, currentWindow: 2,
                equal: ==))
        XCTAssertFalse(
            focusMatches(
                capturedElement: 1, currentElement: 3, capturedWindow: 2, currentWindow: 2,
                equal: ==))
        XCTAssertFalse(
            focusMatches(
                capturedElement: 1, currentElement: 1, capturedWindow: 2, currentWindow: 3,
                equal: ==))
        XCTAssertTrue(
            focusMatches(
                capturedElement: nil, currentElement: 1, capturedWindow: 2, currentWindow: 2,
                equal: ==))
    }

    func testModifierWaitCancellationAndOwnership() throws {
        var waits = 0
        XCTAssertThrowsError(
            try waitForPasteModifiers(
                modifiersHeld: { true }, isCurrent: { waits == 0 }, timedOut: { false },
                pause: { waits += 1 })
        ) { XCTAssertEqual($0 as? FocusError, .cancelled) }
        XCTAssertEqual(waits, 1)
        XCTAssertNoThrow(
            try waitForPasteModifiers(
                modifiersHeld: { false }, isCurrent: { true }, timedOut: { true }, pause: {}))
        XCTAssertThrowsError(
            try verifyPasteOwnership(expected: 2, current: { 3 }, isCurrent: { true })
        ) { XCTAssertEqual($0 as? FocusError, .clipboardChanged) }
        XCTAssertThrowsError(
            try verifyPasteOwnership(expected: 2, current: { 2 }, isCurrent: { false })
        ) { XCTAssertEqual($0 as? FocusError, .cancelled) }
    }

    func testShiftIntentIsCapturedAtStop() async {
        let target = FakeTarget()
        let clipboard = FakeClipboard()
        var shift = true
        let service = InsertionService(
            focus: FakeFocus(
                ticket: FocusTicket { FocusResult(target: target, disposition: .editable) }),
            clipboard: clipboard,
            options: {
                InsertionOptions(
                    simulateTyping: false, sendOnShift: true, restoreClipboard: true,
                    allowClipboardHistory: true)
            },
            accessibilityGranted: { true }, shiftHeld: { shift })
        let ticket = service.captureAtStop()
        shift = false
        let outcome = await service.deliver("hello", to: ticket, autoPaste: true) { true }
        XCTAssertEqual(outcome.delivery, .delivered)
        XCTAssertEqual(target.calls, ["paste: hello", "return"])
    }

}
