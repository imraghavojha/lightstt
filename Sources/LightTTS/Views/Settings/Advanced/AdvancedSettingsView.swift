import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var advancedPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    controller.showAdvanced = false
                } label: {
                    Image(systemName: "chevron.left").frame(width: 28, height: 28).background(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [Color(white: 0.29), Color(white: 0.22)]
                                : [Color(white: 0.99), Color(white: 0.92)], startPoint: .top,
                            endPoint: .bottom), in: Circle()
                    ).overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 0.5))
                }.buttonStyle(.responsive).help("Back to Configuration")
                Text("Advanced settings").font(.system(size: 13, weight: .bold))
                Spacer()
            }.padding(.horizontal, 12).frame(height: 48)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    advancedHeading("Application")
                    recordingBehaviorCard
                    advancedHeading("Voice model")
                    modelResidencyCard
                    advancedHeading("Audio processing")
                    audioProcessingCard
                    advancedHeading("App folder location")
                    historyFolderCard
                    if controller.historyMigration != nil {
                        Text(
                            "Moving recordings… Recording and deletion are temporarily unavailable."
                        ).font(.caption).foregroundStyle(.secondary)
                    }
                    if !controller.message.isEmpty {
                        InlineStatus(
                            message: controller.message, dismiss: { controller.message = "" }
                        ).padding(.top, 12)
                    }
                    advancedHeading("Text input")
                    textInputCard
                }.padding(.horizontal, 24).padding(.bottom, 24).environment(
                    \.advancedSettingsRows, true)
            }.font(.system(size: 13))
        }
    }
    func advancedHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold)).padding(
            .top, title == "Application" ? 14 : 22
        ).padding(.bottom, 9)
    }
}
