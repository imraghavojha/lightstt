import AppKit
import ApplicationServices
import LightTTSRuntime

extension FocusTarget: TextTarget {}

@MainActor
struct NativeFocusCapture: FocusCapturing {
    func captureAtStop() -> FocusTicket {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let task = Task.detached(priority: .userInitiated) {
            FocusTarget.capture(frontPID: pid)
        }
        return FocusTicket {
            let capture = await task.value
            if capture.secure {
                return FocusResult(target: nil, disposition: .secure)
            }
            guard let target = capture.target else {
                return FocusResult(target: nil, disposition: .unavailable)
            }
            return FocusResult(target: target, disposition: target.stopDisposition)
        }
    }
}

@MainActor
struct NativeTranscriptClipboard: TranscriptClipboard {
    func write(_ text: String, allowClipboardHistory: Bool) {
        let item = transcriptPasteboardItem(text, allowClipboardHistory: allowClipboardHistory)
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([item])
    }
}

@MainActor
func makeNativeInsertionService() -> InsertionService {
    InsertionService(
        focus: NativeFocusCapture(), clipboard: NativeTranscriptClipboard(),
        options: {
            let defaults = UserDefaults.standard
            return InsertionOptions(
                simulateTyping: false, sendOnShift: defaults.bool(forKey: "sendOnShift"),
                restoreClipboard: defaults.object(forKey: "restoreClipboard") as? Bool ?? true,
                allowClipboardHistory: defaults.object(forKey: "clipboardHistory") as? Bool ?? true)
        }, accessibilityGranted: { AXIsProcessTrusted() },
        shiftHeld: { CGEventSource.flagsState(.combinedSessionState).contains(.maskShift) })
}
