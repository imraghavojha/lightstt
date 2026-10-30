import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var textInputCard: some View {
        SettingsCard {
            ConfigurationApplicationRow(
                title: "Clipboard content",
                help: "Choose whether to restore the previous clipboard contents"
            ) {
                NeutralSettingsPopup(
                    selection: Binding(
                        get: { restoreClipboard ? 1 : 0 }, set: { restoreClipboard = $0 == 1 }),
                    options: [(0, "Keep result"), (1, "Restore previous")], width: 145
                ).frame(width: 145, height: 28)
            }
            PageRule()
            ConfigurationApplicationRow(
                title: "Clipboard history", help: "Allow clipboard managers to save transcripts"
            ) {
                Toggle("", isOn: $clipboardHistory).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Clipboard history"))
            }
            PageRule()
            ConfigurationApplicationRow(
                title: "Paste result text", help: "Paste the transcription into the focused app"
            ) {
                Toggle("", isOn: $pasteResult).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Paste result text"))
            }
            PageRule()
            ConfigurationApplicationRow(
                title: "Hold shift to auto-send after paste", help: "Send Return when Shift is held"
            ) {
                Toggle("", isOn: $sendOnShift).labelsHidden().toggleStyle(
                    ReferenceSwitchStyle(label: "Hold shift to auto-send after paste"))
            }

        }
    }
}
