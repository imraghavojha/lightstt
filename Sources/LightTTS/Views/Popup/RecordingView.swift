import SwiftUI
import AppKit

struct RecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var level: RecordingLevel
    @State private var hoveringError = false
    init(controller: AppController) { self.controller = controller; self.level = controller.recordingLevel }

    private var capsuleWidth: CGFloat {
        switch controller.state {
        case "error":
            let textWidth = (controller.message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            return min(360, max(100, ceil(textWidth) + 66))
        case "done" where controller.copiedToClipboard:
            let textWidth = ("Copied to clipboard" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
            return ceil(textWidth) + 48
        case "loading":
            let textWidth = ("Loading model…" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
            return ceil(textWidth) + 28
        default: return controller.state == "idle" ? 45 : 60
        }
    }

    var body: some View {
        let idle = controller.state == "idle"
        let isError = controller.state == "error"
        let panelWidth = max(240, capsuleWidth + 20)
        HStack(spacing: 2) {
            if controller.state == "recording" {
                HStack(spacing: 2) {
                    ForEach(0..<6) { index in
                        Capsule().fill(.white)
                            .frame(width: 2, height: max(2, 2 + CGFloat(level.value) * [6, 10, 14, 14, 10, 6][index]))
                    }
                }.offset(x: -1)
            } else if controller.state == "loading" {
                Text("Loading model…").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            } else if controller.state == "processing" {
                Image(systemName: "waveform").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            } else if controller.state == "done" {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                if controller.copiedToClipboard {
                    Text("Copied to clipboard").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).padding(.leading, 4)
                }
            } else if controller.state == "error" {
                Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.white)
                    .help(controller.message)
                Text(controller.message).font(.system(size: 11)).foregroundStyle(.white)
                    .lineLimit(3).truncationMode(.tail).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .help(controller.message).padding(.leading, 4)
                Button(action: { controller.cancel() }) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                }.buttonStyle(.plain).help("Dismiss")
            }
        }
        .contentShape(Capsule())
        .onTapGesture { if controller.state == "error" { controller.cancel() } }
        .onHover { hoveringError = $0 }
        .task(id: "\(controller.state):\(controller.message):\(hoveringError)") {
            guard controller.state == "error", !hoveringError else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && controller.state == "error" { controller.cancel() }
        }
        .padding(.horizontal, isError ? 14 : 0)
        .padding(.vertical, isError ? 10 : 0)
        .frame(width: capsuleWidth, height: isError ? nil : (idle ? 8 : 32))
        .frame(minHeight: isError ? 32 : 0)
        .background(idle ? Color(red: 31/255, green: 31/255, blue: 34/255) : Color(red: 11/255, green: 11/255, blue: 12/255), in: Capsule())
        .overlay(Capsule().strokeBorder(idle ? Color(red: 79/255, green: 79/255, blue: 80/255) : Color(red: 64/255, green: 64/255, blue: 64/255), lineWidth: 1))
        .shadow(color: idle ? .clear : .black.opacity(0.12), radius: 6, y: 4)
        .offset(y: idle ? 0 : -9.5)
        .animation(.easeOut(duration: 0.15), value: idle)
        .animation(.easeOut(duration: 0.08), value: level.value)
        .frame(width: panelWidth, height: 160)
        .background(PanelSizer(width: panelWidth))
        .accessibilityLabel(controller.state == "error" ? controller.message : (controller.state == "done" && controller.copiedToClipboard ? "Done, copied to clipboard" : controller.state.capitalized))
    }
}

// Keep the panel centered as the hosted content changes width, without animating
// or moving its vertical anchor. The normal recording panel remains 240 × 160.
private struct PanelSizer: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) { view.panelWidth = width }

    final class SizingView: NSView {
        var panelWidth: CGFloat = 240 { didSet { resizePanel() } }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resizePanel() }
        private func resizePanel() {
            guard let window, abs(window.frame.width - panelWidth) > 0.5 else { return }
            var frame = window.frame
            frame.origin.x += (frame.width - panelWidth) / 2
            frame.size.width = panelWidth
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame { frame.origin.x = min(max(frame.origin.x, visible.minX), visible.maxX - frame.width) }
            window.setFrame(frame, display: true, animate: false)
        }
    }
}
