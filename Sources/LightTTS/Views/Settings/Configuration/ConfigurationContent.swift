import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var configurationPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PermissionsCard(controller: controller)
                appearanceCard
                Text("Keyboard Shortcuts").font(.system(size: 13, weight: .medium)).padding(
                    .top, 18
                ).padding(.bottom, 9)
                keyboardShortcutsCard
                Text("Application").font(.system(size: 13, weight: .semibold)).padding(.top, 18)
                    .padding(.bottom, 9)
                applicationCard
                SettingsCard {
                    Button {
                        controller.showAdvanced.toggle()
                    } label: {
                        HStack {
                            Text("Advanced settings")
                            Spacer()
                            Image(
                                systemName: controller.showAdvanced
                                    ? "chevron.down" : "chevron.right"
                            ).foregroundStyle(.secondary)
                        }.frame(height: 48).contentShape(Rectangle())
                    }.buttonStyle(.responsive)
                }.padding(.top, 18)
                if !controller.message.isEmpty {
                    InlineStatus(message: controller.message, dismiss: { controller.message = "" })
                        .padding(.top, 12)
                }
            }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
        }.clipped().font(.system(size: 13))
    }
    var retentionLabel: String {
        [
            0: "Forever", 1: "1 day", 7: "1 week", 14: "2 weeks", 30: "1 month", 180: "6 months",
            365: "1 year",
        ][retention] ?? "Forever"
    }
    var retentionBinding: Binding<Int> {
        Binding(
            get: { retention },
            set: { value in
                if value > 0 && (retention == 0 || value < retention) {
                    let alert = NSAlert()
                    alert.messageText = "Delete older recordings?"
                    alert.informativeText =
                        "Recordings older than the selected retention period will be permanently deleted."
                    alert.addButton(withTitle: "Delete Older Recordings")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                }
                retention = value
                controller.pruneHistory()
            })
    }
}
