import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var historyFolderCard: some View {
        SettingsCard {
            HStack(spacing: 10) {
                Text(controller.historyURL.deletingLastPathComponent().path).lineLimit(1)
                    .truncationMode(.middle).help(
                        controller.historyURL.deletingLastPathComponent().path)
                Spacer(minLength: 8)
                Button("Change folder") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        do { try controller.changeHistoryFolder(url) } catch {
                            controller.message = error.localizedDescription
                        }
                    }
                }.disabled(controller.historyMigration != nil)
                if let progress = controller.historyMigration {
                    ProgressView(progress).frame(width: 100)
                    Button("Cancel") { progress.cancel() }
                }
            }.frame(minHeight: 46)
        }
    }
}
