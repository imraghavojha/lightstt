import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

private enum SettingsTab: String, CaseIterable {
    case sound = "Sound", models = "Models", library = "Library", configuration = "Configuration"
    var icon: String { switch self { case .sound: "speaker.wave.2.fill"; case .models: "books.vertical.fill"; case .library: "clock.arrow.circlepath"; case .configuration: "gearshape.fill" } }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @AppStorage("theme") private var theme = "Auto"
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    Button { controller.settingsSelection = tab.rawValue } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(.gray.gradient, in: RoundedRectangle(cornerRadius: 5))
                            Text(tab.rawValue).font(.system(size: 14, weight: .medium))
                            Spacer()
                        }.padding(.horizontal, 8).frame(height: 35).background(controller.settingsSelection == tab.rawValue ? Color.primary.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button(attached ? "Detach into window" : "Back to menu", action: detach).buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12)).padding(8)
            }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 185).frame(maxHeight: .infinity).background(Color(nsColor: scheme == .dark ? NSColor(srgbRed: 0.22, green: 0.235, blue: 0.26, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(controller.settingsSelection).font(.system(size: 14, weight: .bold))
                    Spacer()
                    Menu { Button("System Default") { UserDefaults.standard.set("", forKey: "inputDevice") }; Divider(); ForEach(AVCaptureDevice.devices(for: .audio), id: \.uniqueID) { device in Button(device.localizedName) { UserDefaults.standard.set(device.uniqueID, forKey: "inputDevice") } } } label: { Image(systemName: "mic.fill").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.menuStyle(.borderlessButton).fixedSize().help("Select microphone")
                }.padding(.horizontal, 16).frame(height: 48)
                switch controller.settingsSelection {
                case "Sound": SoundPageView()
                case "Models": ModelsPageView()
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: scheme == .dark ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
        }.frame(width: 750, height: 508).preferredColorScheme(theme == "Dark" ? .dark : theme == "Light" ? .light : nil)
    }
}

struct ModelsPageView: View { var body: some View { Spacer() } }

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { content }.padding(.horizontal, 16).background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08))) }
}
private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View { HStack { Text(title); Spacer(); content }.frame(minHeight: 48) }
}
private struct SoundPageView: View {
    @AppStorage("soundEffects") private var sound = "Classic"
    @AppStorage("soundVolume") private var volume = 0.8
    @AppStorage("recordingSound") private var recordingSound = "Keep Playing"
    @AppStorage("increaseMicVolume") private var increaseMic = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                SettingsRow(title: "Sound effects") { Picker("Sound effects", selection: $sound) { ForEach(["Simple", "Classic", "Off"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 168) }
                Divider()
                SettingsRow(title: "Volume") { Button { playSound(start: true) } label: { Image(systemName: "speaker.fill") }.buttonStyle(.plain); Slider(value: $volume).frame(width: 190); Button { playSound(start: false) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain) }
            }
            Text("Recording").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Sound while recording") { Picker("Sound while recording", selection: $recordingSound) { Text("Keep Playing").tag("Keep Playing"); Text("Mute").tag("Mute"); Text("Lower").tag("Lower") }.labelsHidden().frame(width: 145) }
                Divider()
                SettingsRow(title: "Automatically increase microphone volume") { Image(systemName: "questionmark.circle").help("Increase input volume while recording"); Toggle("", isOn: $increaseMic).labelsHidden().toggleStyle(.switch).tint(.pink) }
            }
        }.padding(.horizontal, 24).padding(.top, 16) }.font(.system(size: 14))
    }
    private func playSound(start: Bool) { AudioSettings.cue(start: start) }
}
private struct LibraryPageView: View {
    @ObservedObject var controller: AppController
    var filtered: [HistoryEntry] { controller.history.filter { controller.historySearch.isEmpty || $0.text.localizedCaseInsensitiveContains(controller.historySearch) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search recordings", text: $controller.historySearch).textFieldStyle(.roundedBorder)
            if let item = controller.selectedHistory {
                Button("‹  Back") { controller.selectedHistory = nil }.buttonStyle(.plain)
                ScrollView { Text(item.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                HStack { Text(item.date, style: .date).foregroundStyle(.secondary); Spacer(); Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id); controller.selectedHistory = nil } }
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                    if filtered.isEmpty { Text(controller.historySearch.isEmpty ? "No recordings yet" : "No recordings found").foregroundStyle(.secondary).padding(.top, 20) }
                    ForEach(filtered) { item in
                        Button { controller.selectedHistory = item } label: { HStack { Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(16).background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
                        .contextMenu { Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id) } }
                    }
                } }
            }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
    }
    private func copy(_ item: HistoryEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string) }
}
private struct ConfigurationPageView: View {
    @ObservedObject var controller: AppController
    @AppStorage("theme") private var theme = "Auto"
    @AppStorage("recordingWindow") private var recordingWindow = "Classic"
    @AppStorage("alwaysShowRecording") private var alwaysShow = false
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
    @AppStorage("cancelHotkeyCode") private var cancelHotkeyCode = 53
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("restoreClipboard") private var restoreClipboard = true
    @AppStorage("pasteResult") private var pasteResult = true
    @AppStorage("historyRetentionDays") private var retention = 0
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                HStack(alignment: .top) { Text("Theme").padding(.top, 16); Spacer(); choices(["Auto", "Light", "Dark"], selection: $theme, icons: ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"]) }.padding(.vertical, 12)
                Divider()
                HStack(alignment: .top) { Text("Recording window").padding(.top, 16); Spacer(); choices(["Classic", "Mini", "None"], selection: $recordingWindow, icons: ["waveform", "waveform", "eye.slash"]) }.padding(.vertical, 12)
                Divider()
                SettingsRow(title: "Always show") { Image(systemName: "questionmark.circle").help("Keep the mini recording window visible"); Toggle("", isOn: $alwaysShow).labelsHidden().toggleStyle(.switch).tint(.pink).disabled(recordingWindow != "Mini") }
            }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }.onChange(of: alwaysShow) { _ in controller.refreshRecordingWindow() }
            Text("Keyboard Shortcuts").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                shortcutRow("Toggle Recording", subtitle: "Starts and stops recordings", key: "hotkeyCode", modifiers: "hotkeyModifiers", fallback: 49); Divider()
                shortcutRow("Cancel Recording", subtitle: "Discards the active recording", key: "cancelHotkeyCode", modifiers: nil, fallback: 53); Divider()
                SettingsRow(title: "Push to Talk") { Toggle("", isOn: $pushToTalk).labelsHidden().toggleStyle(.switch).tint(.pink) }; Divider()
                SettingsRow(title: "Use Right Option only") { Toggle("", isOn: $rightOption).labelsHidden().toggleStyle(.switch).tint(.pink) }
            }
            Text("Application").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Launch on login") { Toggle("", isOn: $controller.loginEnabled).labelsHidden().toggleStyle(.switch).tint(.pink).onChange(of: controller.loginEnabled) { value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { controller.loginEnabled = SMAppService.mainApp.status == .enabled; controller.message = error.localizedDescription } } }; Divider()
                SettingsRow(title: "Keep recordings for") { Picker("Keep recordings for", selection: retentionBinding) { Text("Forever").tag(0); Text("1 day").tag(1); Text("1 week").tag(7); Text("2 weeks").tag(14); Text("1 month").tag(30); Text("6 months").tag(180); Text("1 year").tag(365) }.labelsHidden().frame(width: 140) }; Divider()
                SettingsRow(title: "Paste result text") { Toggle("", isOn: $pasteResult).labelsHidden().toggleStyle(.switch).tint(.pink) }; Divider()
                SettingsRow(title: "Restore clipboard after pasting") { Toggle("", isOn: $restoreClipboard).labelsHidden().toggleStyle(.switch).tint(.pink).disabled(!pasteResult) }; Divider()
                SettingsRow(title: "Accessibility") { Button("Request Access") { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) } }
            }
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24) }.font(.system(size: 14))
    }
    private var retentionBinding: Binding<Int> {
        Binding(get: { retention }, set: { value in
            if value > 0 && (retention == 0 || value < retention) {
                let alert = NSAlert(); alert.messageText = "Delete older recordings?"; alert.informativeText = "Recordings older than the selected retention period will be permanently deleted."; alert.addButton(withTitle: "Delete Older Recordings"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            retention = value; controller.pruneHistory()
        })
    }
    private func choices(_ values: [String], selection: Binding<String>, icons: [String]) -> some View {
        HStack(spacing: 12) { ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            Button { selection.wrappedValue = value } label: { VStack(spacing: 5) {
                Image(systemName: icons[index]).font(.system(size: 20)).frame(width: 80, height: 44).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.wrappedValue == value ? Color.blue : Color.primary.opacity(0.15), lineWidth: selection.wrappedValue == value ? 2 : 1))
                Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
            } }.buttonStyle(.plain)
        } }
    }
    private func shortcutRow(_ title: String, subtitle: String, key: String, modifiers: String?, fallback: Int) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(title); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button { UserDefaults.standard.removeObject(forKey: key); if let modifiers { UserDefaults.standard.removeObject(forKey: modifiers) }; controller.objectWillChange.send() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain); ShortcutRecorder(codeKey: key, modifiersKey: modifiers, fallbackCode: fallback).id("\(key)-\(hotkeyCode)-\(hotkeyModifiers)-\(cancelHotkeyCode)").frame(width: 100, height: 28) }.frame(minHeight: 50)
    }
}
