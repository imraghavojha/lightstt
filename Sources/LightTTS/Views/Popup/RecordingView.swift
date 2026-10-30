import SwiftUI
struct RecordingView: View {
    @ObservedObject var controller: AppController
    var body: some View {
        HStack(spacing: 12) {
            if controller.state == "recording" {
                Circle().fill(.red).frame(width: 8, height: 8)
                HStack(spacing: 3) { ForEach(0..<20) { i in Capsule().fill(.primary).frame(width: 3, height: max(3, CGFloat(controller.level) * CGFloat(12 + (i % 5) * 4))) } }.frame(height: 34)
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text(timerInterval: controller.started...Date.distantFuture, countsDown: false).monospacedDigit().frame(width: 58) }
            } else if controller.state == "processing" { ProgressView().controlSize(.small); Text("Processing…") }
            else if controller.state == "error" { Image(systemName: "exclamationmark.circle"); Text(controller.message).font(.caption).lineLimit(2) }
            else { Image(systemName: "checkmark"); Text("Done") }
            Spacer(minLength: 0)
        }.padding(.horizontal, 18).frame(width: 300, height: 64).background(.regularMaterial, in: Capsule())
    }
}
