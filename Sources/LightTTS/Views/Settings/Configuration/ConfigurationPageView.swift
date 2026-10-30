import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

struct ConfigurationPageView: View {
    @Environment(\.colorScheme) var scheme
    @ObservedObject var controller: AppController
    @AppStorage("theme") var theme = "Auto"
    @AppStorage("modelIdleTimeoutSeconds") var modelIdleTimeout = 300
    @AppStorage("historyFolder") var historyFolder = ""
    @AppStorage("recordingWindow") var recordingWindow = "Mini"
    @AppStorage("hotkeyCode") var hotkeyCode = 49
    @AppStorage("hotkeyModifiers") var hotkeyModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
    @AppStorage("cancelHotkeyCode") var cancelHotkeyCode = 53
    @AppStorage("mouseShortcut") var mouseShortcut = -1
    @AppStorage("pushShortcutEnabled") var pushShortcutEnabled = false
    @AppStorage("pushHotkeyCode") var pushHotkeyCode = 49
    @AppStorage("pushHotkeyModifiers") var pushHotkeyModifiers = Int(
        NSEvent.ModifierFlags.option.union(.shift).rawValue)
    @AppStorage("rightOption") var rightOption = false
    @AppStorage("restoreClipboard") var restoreClipboard = true
    @AppStorage("autoPaste") var pasteResult = true
    @AppStorage("sendOnShift") var sendOnShift = false
    @AppStorage("removeSilence") var removeSilence = false
    @AppStorage("normalizeAudio") var normalizeAudio = false
    @AppStorage("historyRetentionDays") var retention = 0
    @AppStorage("recordOnMenubarClick") var recordOnMenubarClick = false
    @AppStorage("closeAfterTranscription") var closeAfterTranscription = false
    @AppStorage("clipboardHistory") var clipboardHistory = true
    var body: some View {
        Group { if controller.showAdvanced { advancedPage } else { configurationPage } }
            .onAppear { controller.refreshLoginStatus() }
            .onDisappear { controller.showAdvanced = false }
    }
}
