import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

private struct AdvancedSettingsRowsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var advancedSettingsRows: Bool {
        get { self[AdvancedSettingsRowsKey.self] }
        set { self[AdvancedSettingsRowsKey.self] = newValue }
    }
}

struct ConfigurationApplicationRow<Content: View>: View {
    @Environment(\.advancedSettingsRows) private var advanced
    let title: String
    var help: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if let help {
                Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(help)
            }
            Spacer()
            content
        }.frame(
            minHeight: title == "Keep recordings for"
                ? 58 : (advanced ? (title == "Voice model active duration" ? 60 : 46) : 43))
    }
}
