import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var modelResidencyCard: some View {
        SettingsCard {
            ConfigurationApplicationRow(
                title: "Voice model active duration",
                help: "Unload the voice model after this period of inactivity"
            ) {
                NeutralSettingsPopup(
                    selection: $modelIdleTimeout,
                    options: [
                        (60, "1 minute"), (120, "2 minutes"), (300, "5 minutes"),
                        (600, "10 minutes"), (1800, "30 minutes"),
                    ], width: 125
                ).frame(width: 125, height: 28).onChange(of: modelIdleTimeout) { _ in
                    controller.refreshModelIdleTimeout()
                }
            }
        }
    }
}
