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
            }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 185).frame(maxHeight: .infinity).background(Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.75 : 0.9))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(controller.settingsSelection).font(.system(size: 14, weight: .bold))
                    Spacer()
                    Menu { ForEach(AVCaptureDevice.devices(for: .audio), id: \.uniqueID) { device in Button(device.localizedName) { UserDefaults.standard.set(device.uniqueID, forKey: "inputDevice") } } } label: { Image(systemName: "mic.fill").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.menuStyle(.borderlessButton).fixedSize().disabled(true).help("Microphone selection is not yet implemented")
                }.padding(.horizontal, 16).frame(height: 48)
                switch controller.settingsSelection {
                case "Sound": SoundPageView()
                case "Models": ModelsPageView()
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor))
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
    @AppStorage("recordingSound") private var recordingSound = "Pause"
    @AppStorage("increaseMicVolume") private var increaseMic = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                SettingsRow(title: "Sound effects") { Picker("Sound effects", selection: $sound) { ForEach(["Simple", "Classic", "Off"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 168).disabled(true) }
                Divider()
                SettingsRow(title: "Volume") { Button { playSound(start: true) } label: { Image(systemName: "speaker.fill") }.buttonStyle(.plain); Slider(value: $volume).frame(width: 190); Button { playSound(start: false) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain) }
            }
            Text("Recording").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Sound while recording") { Picker("Sound while recording", selection: $recordingSound) { Text("Pause").tag("Pause"); Text("Mute").tag("Mute"); Text("Continue").tag("Continue") }.labelsHidden().frame(width: 145).disabled(true) }
                Divider()
                SettingsRow(title: "Automatically increase microphone volume") { Image(systemName: "questionmark.circle").help("Increase input volume while recording"); Toggle("", isOn: $increaseMic).labelsHidden().tint(.pink).disabled(true) }
            }
        }.padding(.horizontal, 24).padding(.top, 16) }.font(.system(size: 14))
    }
    private func playSound(start: Bool) { if let sound = NSSound(named: NSSound.Name(start ? "Tink" : "Pop")) { sound.volume = Float(volume); sound.play() } }
}
private struct LibraryPageView: View {
    @ObservedObject var controller: AppController
    @State private var search = ""
    @State private var selected: HistoryEntry?
    var filtered: [HistoryEntry] { controller.history.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search recordings", text: $search).textFieldStyle(.roundedBorder)
            if let item = selected {
                Button("‹  Back") { selected = nil }.buttonStyle(.plain)
                ScrollView { Text(item.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                HStack { Text(item.date, style: .date).foregroundStyle(.secondary); Spacer(); Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id); selected = nil } }
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                    if filtered.isEmpty { Text(search.isEmpty ? "No recordings yet" : "No recordings found").foregroundStyle(.secondary).padding(.top, 20) }
                    ForEach(filtered) { item in
                        Button { selected = item } label: { HStack { Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "chevron.right").foregroundStyle(.secondary) }.padding(16).background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
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
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    @AppStorage("restoreClipboard") private var restoreClipboard = true
    @State private var login = SMAppService.mainApp.status == .enabled
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            SettingsCard { SettingsRow(title: "Theme") { Picker("Theme", selection: $theme) { ForEach(["Auto", "Light", "Dark"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 200) } }
            Text("Keyboard Shortcuts").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Push to Talk") { Toggle("", isOn: $pushToTalk).labelsHidden().tint(.pink) }; Divider()
                SettingsRow(title: "Use Right Option only") { Toggle("", isOn: $rightOption).labelsHidden().tint(.pink) }; Divider()
                SettingsRow(title: "Option + key code") { TextField("49", value: $hotkeyCode, format: .number).frame(width: 60).disabled(rightOption) }
            }
            Text("Application").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Launch on login") { Toggle("", isOn: $login).labelsHidden().tint(.pink).onChange(of: login) { value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { login = SMAppService.mainApp.status == .enabled; controller.message = error.localizedDescription } } }; Divider()
                SettingsRow(title: "Restore clipboard after pasting") { Toggle("", isOn: $restoreClipboard).labelsHidden().tint(.pink) }; Divider()
                SettingsRow(title: "Accessibility") { Button("Request Access") { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) } }
            }
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24) }.font(.system(size: 14))
    }
}
