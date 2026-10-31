import AppKit
import SwiftUI

/// Dynamic Island style: the notch grows a wing on each side while a session is active,
/// so nothing covers the content of the screen. Errors drop down below the notch.
struct IslandRecordingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var level: RecordingLevel
    let metrics: IslandMetrics

    init(controller: AppController, metrics: IslandMetrics) {
        self.controller = controller
        self.level = controller.recordingLevel
        self.metrics = metrics
    }

    private var state: String { controller.state }
    private var expanded: Bool { state != "idle" }
    private var isError: Bool { state == "error" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading.frame(width: IslandMetrics.wing)
                Spacer(minLength: metrics.notchWidth)
                trailing.frame(width: IslandMetrics.wing)
            }
            .frame(height: metrics.notchHeight)
            .opacity(expanded ? 1 : 0)
            if isError {
                HStack(spacing: 8) {
                    Text(controller.message).font(.system(size: 11)).foregroundStyle(.white)
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: { controller.cancel() }) {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8)).frame(width: 22, height: 22)
                    }.buttonStyle(.plain).help("Dismiss")
                }
                .padding(.horizontal, 14).padding(.bottom, 4).frame(height: 40)
                .transition(.opacity)
            }
        }
        .frame(width: expanded ? metrics.expandedWidth : metrics.notchWidth, alignment: .top)
        .background(
            UnevenRoundedRectangle(
                bottomLeadingRadius: isError ? 16 : 11, bottomTrailingRadius: isError ? 16 : 11
            ).fill(.black)
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { if isError { controller.cancel() } }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isError)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isError ? controller.message : state.capitalized)
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case "recording":
            Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 8, height: 8)
                .opacity(0.55 + 0.45 * Double(min(1, level.value * 3)))
        case "starting":
            Circle().fill(.white.opacity(0.4)).frame(width: 8, height: 8)
        case "loading", "processing":
            ProgressView().progressViewStyle(.circular).controlSize(.small).scaleEffect(0.7)
        case "done":
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
        case "error":
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case "recording", "starting":
            HStack(spacing: 2) {
                ForEach(0..<6) { index in
                    Capsule().fill(.white.opacity(state == "recording" ? 1 : 0.4))
                        .frame(
                            width: 2.5,
                            height: max(3, 3 + CGFloat(level.value) * [5, 9, 13, 13, 9, 5][index]))
                }
            }.animation(.easeOut(duration: 0.08), value: level.value)
        case "loading", "processing":
            Button(action: { controller.cancel() }) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).frame(width: 24, height: 24)
            }.buttonStyle(.plain).help("Cancel transcription")
                .accessibilityLabel("Cancel transcription")
        case "done" where controller.copiedToClipboard:
            Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8)).help("Copied to clipboard")
        default:
            EmptyView()
        }
    }
}
