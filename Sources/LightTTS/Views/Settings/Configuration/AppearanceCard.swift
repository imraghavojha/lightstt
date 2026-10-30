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
                Text("Recording window").padding(.top, 1)
                Spacer()
                choices(
                    ["Classic", "Mini", "None"], selection: $recordingWindow,
                    icons: ["waveform", "waveform", "eye.slash"]
                ).padding(.trailing, 4)
            }.padding(.top, 12).padding(.bottom, 10)
            PageRule()
            HStack(spacing: 8) {
                Text("Always show")
                Image(systemName: "questionmark.circle").help(
                    "Keep the mini recording window visible")
                Spacer()
                Toggle("", isOn: $alwaysShow).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Always show")
                ).disabled(recordingWindow != "Mini")
            }.frame(height: 45)
        }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }.onChange(
            of: alwaysShow
        ) { _ in controller.refreshRecordingWindow() }
    }
}
