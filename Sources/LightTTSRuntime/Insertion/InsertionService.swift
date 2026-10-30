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
        var copied = false
        if !accessibilityGranted() {
            warning =
                "Grant Accessibility to auto-paste. The transcription was copied to the clipboard."
        } else if case .secure = result.disposition {
            copied = true
        } else if case .unavailable = result.disposition {
            copied = true
        } else if let target = result.target {
            let send = settings.sendOnShift && shiftHeld()
            do {
                let started = try await Task.detached(priority: .userInitiated) {
                    guard await isCurrent() else { return false }
                    try target.paste(
                        text,
                        restoreClipboard: shouldRestoreClipboard(
                            disposition: result.disposition, preference: settings.restoreClipboard),
                        allowClipboardHistory: settings.allowClipboardHistory)
                    if send { try target.sendReturn() }
                    return true
                }.value
                guard started else { return InsertionOutcome(delivery: .skipped) }
            } catch FocusError.secure {
                copied = true
            } catch {
                warning =
                    "Could not auto-paste: \(error.localizedDescription). The transcription was copied to the clipboard."
            }
        } else {
            copied = true
        }

        guard isCurrent() else { return InsertionOutcome(delivery: .skipped) }
        let clipboardSettings = options()
        if copied || warning != nil {
            clipboard.write(text, allowClipboardHistory: clipboardSettings.allowClipboardHistory)
        }
        return InsertionOutcome(
            delivery: copied || warning != nil ? .copied : .delivered, warning: warning)
    }
}
