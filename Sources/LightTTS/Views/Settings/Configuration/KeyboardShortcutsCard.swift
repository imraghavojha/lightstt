import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

extension ConfigurationPageView {
    var keyboardShortcutsCard: some View {
        SettingsCard {
            shortcutRow(
                "Push to Talk", subtitle: "Separate shortcut: hold to record, release when done",
                key: "pushHotkeyCode", modifiers: "pushHotkeyModifiers", fallback: 49,
                enabled: "pushShortcutEnabled")
            PageRule()
            shortcutRow(
                "Toggle Recording", subtitle: "Press once to start, again to stop",
                key: "hotkeyCode", modifiers: "hotkeyModifiers", fallback: 49)
            PageRule()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mouse shortcut")
                    Text("Tap to toggle, or hold and release when done").font(.system(size: 10))
                        .foregroundStyle(shortcutSubtitleColor)
                }
                Spacer()
                Button {
                    SettingsDefaults.store.set(-1, forKey: "mouseShortcut")
                    NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
                    controller.objectWillChange.send()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Disable mouse shortcut").help("Disable mouse shortcut")
                MouseShortcutRecorder().fixedSize().frame(height: 28)
            }.frame(minHeight: 50)
            PageRule()
            shortcutRow(
                "Cancel Recording", subtitle: "Discards the active recording",
                key: "cancelHotkeyCode", modifiers: "cancelHotkeyModifiers", fallback: 53)
        }
    }
}

extension ConfigurationPageView {
    var shortcutSubtitleColor: Color {
        scheme == .dark
            ? Color(red: 217 / 255, green: 218 / 255, blue: 222 / 255) : Color(white: 93 / 255)
    }
    func shortcutRow(
        _ title: String, subtitle: String, key: String, modifiers: String?, fallback: Int,
        enabled: String? = nil
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(shortcutSubtitleColor)
            }
            Spacer()
            Button {
                if let enabled {
                    SettingsDefaults.store.set(false, forKey: enabled)
                } else {
                    ShortcutButton.reset(codeKey: key, modifiersKey: modifiers)
                }
                NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
                controller.objectWillChange.send()
            } label: {
                Image(systemName: enabled == nil ? "arrow.counterclockwise" : "xmark").font(
                    .system(size: 10)
                ).foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityLabel("\(enabled == nil ? "Reset" : "Disable") \(title) shortcut").help("\(enabled == nil ? "Reset" : "Disable") \(title) shortcut")
            ShortcutRecorder(
                codeKey: key, modifiersKey: modifiers, fallbackCode: fallback, enabledKey: enabled
            ).fixedSize().frame(height: 28)
        }.padding(.trailing, 6).frame(minHeight: 50)
    }
}
