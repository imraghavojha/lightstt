import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var audioProcessingCard: some View {
        SettingsCard {
            ConfigurationApplicationRow(
                title: "Silence removal", help: "Remove silence from recordings"
            ) {
                Toggle("", isOn: $removeSilence).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Silence removal"))
            }
            PageRule()
            ConfigurationApplicationRow(
                title: "Dynamic normalization", help: "Normalize recording volume"
            ) {
                Toggle("", isOn: $normalizeAudio).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Dynamic normalization"))
            }
        }
    }
}
