import SwiftUI

struct RecordingView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        let idle = controller.state == "idle"
        HStack(spacing: 2) {
            if controller.state == "recording" {
                ForEach(0..<6) { index in
                    Capsule().fill(.white)
                        .frame(width: 2, height: max(2, 2 + CGFloat(controller.level) * [6, 10, 14, 14, 10, 6][index]))
                }
            } else if controller.state == "processing" {
                ProgressView().controlSize(.mini).tint(.white)
            } else if controller.state == "done" {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            } else if controller.state == "error" {
                Image(systemName: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.white)
                    .help(controller.message)
            }
        }
        .frame(width: idle ? 48 : 60, height: idle ? 10 : 32)
        .background(Color(red: 0.043, green: 0.043, blue: 0.047), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .animation(.easeOut(duration: 0.15), value: idle)
        .animation(.easeOut(duration: 0.08), value: controller.level)
        .frame(width: 240, height: 160)
        .accessibilityLabel(controller.state == "error" ? controller.message : controller.state.capitalized)
    }
}
