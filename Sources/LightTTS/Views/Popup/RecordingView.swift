import SwiftUI

struct RecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var level: RecordingLevel
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
            } else if controller.state == "processing" {
                ProgressView().controlSize(.mini).environment(\.colorScheme, .dark)
            } else if controller.state == "done" {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            } else if controller.state == "error" {
                Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.white)
                    .help(controller.message)
            }
        }
        .frame(width: idle ? 45 : 60, height: idle ? 8 : 32)
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
