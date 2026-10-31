import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var appearanceCard: some View {
        SettingsCard {
            HStack(alignment: .top) {
                Text("Theme").padding(.top, 2)
                Spacer()
                choices(
                    ["Auto", "Light", "Dark"], selection: $theme,
                    icons: ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"])
            }.padding(.top, 12).padding(.bottom, 4)
            PageRule()
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recording window").padding(.top, 1)
                    if recordingWindow == "Mini" {
                        Text("Drag the window to move it.").font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        if !recordingPanelPosition.isEmpty {
                            Button("Reset position") { controller.resetRecordingWindowPosition() }
                                .buttonStyle(.link).font(.system(size: 11))
                        }
                    }
                }
                Spacer()
                choices(
                    ["Mini", "Island", "None"], selection: $recordingWindow,
                    icons: ["waveform", "capsule.tophalf.filled", "eye.slash"]
                ).padding(.trailing, 4)
            }.padding(.top, 12).padding(.bottom, 10)
        }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }
    }
}
