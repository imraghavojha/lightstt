import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var recordingBehaviorCard: some View {
        SettingsCard {
            ConfigurationApplicationRow(title: "Start recording on menu bar click") {
                Toggle("", isOn: $recordOnMenubarClick).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Start recording on menu bar click"))
            }
            PageRule()
            ConfigurationApplicationRow(title: "Close after transcription") {
                Toggle("", isOn: $closeAfterTranscription).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Close after transcription"))
            }
        }
    }
}
