import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var applicationCard: some View {
        SettingsCard {
            ConfigurationApplicationRow(
                title: "Launch on login", help: "Open LightTTS when you log in"
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { controller.loginEnabled }, set: { controller.setLoginEnabled($0) })
                ).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Launch on login"))
            }
            PageRule()
            ConfigurationApplicationRow(
                title: "Keep recordings for", help: "Automatically remove older recordings"
            ) { RetentionPopup(selection: retentionBinding) }
        }
    }
}
