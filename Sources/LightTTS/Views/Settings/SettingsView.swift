import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

private final class SettingsDialogState: ObservableObject { @Published var deleting: Model? }

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @StateObject private var dialog = SettingsDialogState()
    @StateObject var devices = SettingsDevices()
    @AppStorage("selectedModel") private var selectedModel = ModelDefaults.selectedModel
    @AppStorage("theme") private var theme = "Auto"
    @Environment(\.colorScheme) private var scheme
    private var effectiveTheme: String { ProcessInfo.processInfo.environment["LIGHTTTS_SCREENSHOT_APPEARANCE"] ?? theme }
    var dark: Bool { effectiveTheme == "Dark" || (effectiveTheme == "Auto" && scheme == .dark) }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                if controller.settingsSelection != "Models" && controller.settingsSelection != "Library" && !(controller.settingsSelection == "Configuration" && controller.showAdvanced) {
                    header
                }
                if let operation = controller.modelOperation { HStack { ProgressView().controlSize(.small); Text(operation).font(.caption); Spacer() }.padding(.horizontal, 16).padding(.vertical, 4) }
                switch controller.settingsSelection {
                case "Sound": SoundPageView(controller: controller)
                case "Models": ModelsPageView(controller: controller, deleting: $dialog.deleting)
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.onChange(of: controller.settingsSelection) { UITrace.end("page-\($0)") }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: dark ? NSColor(srgbRed: 43/255, green: 48/255, blue: 53/255, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
        }.frame(minWidth: 750, minHeight: 508, maxHeight: .infinity)
        .foregroundStyle(dark ? Color(red: 233/255, green: 233/255, blue: 234/255) : Color(white: 0.30)).preferredColorScheme(effectiveTheme == "Dark" ? .dark : effectiveTheme == "Light" ? .light : nil).defaultAppStorage(CommandLine.arguments.contains("--ui-fixture") ? SettingsDefaults.store : .standard)
        .background(ConfirmationFrameOverlay(model: dialog.deleting, name: dialog.deleting?.name ?? "", cancel: { dialog.deleting = nil }, delete: { model in
            controller.deleteModel(model); dialog.deleting = nil
        }))
        .onChange(of: selectedModel) { _ in controller.reloadSelectedModel() }
    }
}
