import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct ConfirmationCard: View {
    let model: Model
    let name: String
    let cancel: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color.black.opacity(0.50)
            VStack(alignment: .leading, spacing: 11) {
                Text("Delete \(name)").font(.system(size: 13, weight: .bold))
                Text(
                    model.engine == "apple"
                        ? "LightTTS will forget this selection; macOS manages the speech assets."
                        : model.engine == "cloud"
                            ? "The model and its API key will be removed."
                            : "Are you sure you want to delete this model?"
                ).font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).buttonStyle(
                        AlertButton(destructive: false))
                    Button("Delete", role: .destructive, action: delete).buttonStyle(
                        AlertButton(destructive: true))
                }
            }.padding(20).frame(width: 260).background(
                colorScheme == .dark
                    ? Color(red: 18 / 255, green: 19 / 255, blue: 23 / 255)
                    : Color(red: 179 / 255, green: 180 / 255, blue: 184 / 255),
                in: RoundedRectangle(cornerRadius: 34)
            ).shadow(radius: 18).offset(y: -14)
        }.ignoresSafeArea()
    }
}

private struct AlertButton: ButtonStyle {
    let destructive: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(
            destructive ? Color.red : Color.primary
        ).frame(maxWidth: .infinity).frame(height: 28).background(
            destructive
                ? (colorScheme == .dark
                    ? Color(red: 37 / 255, green: 21 / 255, blue: 22 / 255)
                    : Color.red.opacity(configuration.isPressed ? 0.3 : 0.14))
                : Color.primary.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}
