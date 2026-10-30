import SwiftUI

struct RecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var level: RecordingLevel
    @State private var hoveringError = false
    init(controller: AppController) { self.controller = controller; self.level = controller.recordingLevel }

    var body: some View {
        let idle = controller.state == "idle"
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
            } else if controller.state == "error" {
                Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.white)
                    .help(controller.message)
                Text(controller.message).font(.system(size: 11)).foregroundStyle(.white)
                    .lineLimit(2).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, controller.state == "error" ? 14 : 0)
        .frame(width: idle ? 45 : (controller.state == "error" ? 220 : (controller.state == "loading" ? 120 : 60)), height: idle ? 8 : (controller.state == "error" ? 56 : 32))
        .background(idle ? Color(red: 31/255, green: 31/255, blue: 34/255) : Color(red: 11/255, green: 11/255, blue: 12/255), in: Capsule())
        .overlay(Capsule().strokeBorder(idle ? Color(red: 79/255, green: 79/255, blue: 80/255) : Color(red: 64/255, green: 64/255, blue: 64/255), lineWidth: 1))
        .shadow(color: idle ? .clear : .black.opacity(0.12), radius: 6, y: 4)
        .offset(y: idle ? 0 : -9.5)
        .animation(.easeOut(duration: 0.15), value: idle)
        .animation(.easeOut(duration: 0.08), value: level.value)
        .frame(width: 240, height: 160)
        .accessibilityLabel(controller.state == "error" ? controller.message : controller.state.capitalized)
    }
}
