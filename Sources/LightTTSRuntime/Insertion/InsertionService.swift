import Foundation

@MainActor
public final class InsertionService: InsertionServicing {
    private let focus: any FocusCapturing
    private let clipboard: any TranscriptClipboard
    private let options: () -> InsertionOptions
    private let accessibilityGranted: () -> Bool
    private let shiftHeld: () -> Bool

    public init(
        focus: any FocusCapturing, clipboard: any TranscriptClipboard,
        options: @escaping () -> InsertionOptions,
        accessibilityGranted: @escaping () -> Bool, shiftHeld: @escaping () -> Bool
    ) {
        self.focus = focus
        self.clipboard = clipboard
        self.options = options
        self.accessibilityGranted = accessibilityGranted
        self.shiftHeld = shiftHeld
    }

    public func captureAtStop() -> FocusTicket {
        focus.captureAtStop()
    }

    public func deliver(
        _ text: String, to focus: FocusTicket, autoPaste: Bool,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> InsertionOutcome {
        guard isCurrent() else { return InsertionOutcome(delivery: .skipped) }
        if !autoPaste {
            clipboard.write(text, allowClipboardHistory: options().allowClipboardHistory)
            return InsertionOutcome(delivery: .copied)
        }

        let result = await focus.result()
        guard isCurrent() else { return InsertionOutcome(delivery: .skipped) }
        let settings = options()
        var warning: String?
        if !accessibilityGranted() {
            warning =
                "Grant Accessibility to auto-paste. The transcription was copied to the clipboard."
        } else if case .secure = result.disposition {
            warning = "Copied: secure field"
        } else if case .unavailable = result.disposition {
            warning =
                result.target == nil
                ? "No focused editable field. The transcription was copied to the clipboard."
                : "Could not auto-paste: \(FocusError.unavailable.localizedDescription). The transcription was copied to the clipboard."
        } else if let target = result.target {
            let send = settings.sendOnShift && shiftHeld()
            do {
                let started = try await Task.detached(priority: .userInitiated) {
                    guard await isCurrent() else { return false }
                    try performTextInput(
                        text, simulateTyping: settings.simulateTyping, sendOnShift: send,
                        shiftHeld: true, insert: target.insert, type: target.type,
                        sendReturn: target.sendReturn)
                    return true
                }.value
                guard started else { return InsertionOutcome(delivery: .skipped) }
            } catch FocusError.secure {
                warning = "Copied: secure field"
            } catch {
                warning =
                    "Could not auto-paste: \(error.localizedDescription). The transcription was copied to the clipboard."
            }
        } else {
            warning = "No focused editable field. The transcription was copied to the clipboard."
        }

        guard isCurrent() else { return InsertionOutcome(delivery: .skipped) }
        let clipboardSettings = options()
        if warning != nil || !clipboardSettings.restoreClipboard {
            clipboard.write(text, allowClipboardHistory: clipboardSettings.allowClipboardHistory)
        }
        return InsertionOutcome(delivery: warning == nil ? .delivered : .copied, warning: warning)
    }
}
