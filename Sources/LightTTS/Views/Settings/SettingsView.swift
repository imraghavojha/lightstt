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
    private var dark: Bool { theme == "Dark" || (theme == "Auto" && scheme == .dark) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    Button { controller.settingsSelection = tab.rawValue } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).frame(width: 20, height: 20).background(Color(white: 0.32).gradient, in: RoundedRectangle(cornerRadius: 5))
                            Text(tab.rawValue).font(.system(size: 14, weight: .medium))
                            Spacer()
                        }.padding(.horizontal, 8).frame(height: 35).background(controller.settingsSelection == tab.rawValue ? (dark ? Color.white.opacity(0.16) : Color.white.opacity(0.65)) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button(attached ? "Detach into window" : "Back to menu", action: detach).buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12)).padding(8)
            }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 185).frame(maxHeight: .infinity).background(Color(nsColor: dark ? NSColor(srgbRed: 0.22, green: 0.235, blue: 0.26, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    Text(controller.settingsSelection).font(.system(size: 14, weight: .bold))
                    Spacer()
                    if controller.settingsSelection == "Library" {
                        Button { controller.historySearchVisible.toggle(); if !controller.historySearchVisible { controller.historySearch = "" } } label: { Image(systemName: "magnifyingglass").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.buttonStyle(.plain).help("Search recordings")
                    } else {
                        Menu { Button("System Default") { UserDefaults.standard.set("", forKey: "inputDevice") }; Divider(); ForEach(AVCaptureDevice.devices(for: .audio), id: \.uniqueID) { device in Button(device.localizedName) { UserDefaults.standard.set(device.uniqueID, forKey: "inputDevice") } } } label: { Image(systemName: "mic.fill").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.menuStyle(.borderlessButton).fixedSize().help("Select microphone")
                    }
                }.padding(.horizontal, 16).frame(height: 48)
                switch controller.settingsSelection {
                case "Sound": SoundPageView(controller: controller)
                case "Models": ModelsPageView()
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: dark ? NSColor(srgbRed: 0.1725, green: 0.1843, blue: 0.2039, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
        }.frame(width: 750, height: 508).preferredColorScheme(theme == "Dark" ? .dark : theme == "Light" ? .light : nil)
    }
}

struct ModelsPageView: View { var body: some View { Spacer() } }

private struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { content }.padding(.horizontal, 16).background(scheme == .dark ? Color.white.opacity(0.07) : Color.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08))) }
}
private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View { HStack { Text(title); Spacer(); content }.frame(minHeight: 48) }
}
private struct SoundPageView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var scheme
    @AppStorage("soundEffects") private var sound = "Classic"
    @AppStorage("soundVolume") private var volume = 0.8
    @AppStorage("recordingSound") private var recordingSound = "Pause"
    @AppStorage("increaseMicVolume") private var increaseMic = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                SettingsRow(title: "Sound effects") { Picker("Sound effects", selection: $sound) { ForEach(["Simple", "Classic", "Off"], id: \.self) { Text($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 168) }
                Divider()
                SettingsRow(title: "Volume") { Button { playSound(start: true) } label: { Image(systemName: "speaker.fill") }.buttonStyle(.plain); Slider(value: $volume).tint(scheme == .dark ? .gray : Color(red: 0.90, green: 0.27, blue: 0.60)).frame(width: 190); Button { playSound(start: false) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain) }
            }
            Text("Recording").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Sound while recording") {
                    Menu {
                        ForEach(["Keep Playing", "Pause", "Mute", "Lower", "Muffle"], id: \.self) { value in Button(value) { recordingSound = value } }
                    } label: {
                        HStack(spacing: 8) { Image(systemName: recordingSound == "Pause" ? "pause.circle" : recordingSound == "Mute" ? "speaker.slash" : "speaker.wave.2"); Text(recordingSound); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }.padding(.horizontal, 9)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 145, height: 30).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1))).overlay(alignment: .trailing) { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 9).allowsHitTesting(false) }.help("Pause supports Music and Spotify; Muffle lowers volume if system audio capture is unavailable.")
                }
                Divider()
                HStack { Text("Automatically increase microphone volume"); Image(systemName: "questionmark.circle").help("Increase input volume while recording"); Spacer(); Toggle("", isOn: $increaseMic).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }.frame(minHeight: 48)
            }
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.top, 16) }.font(.system(size: 14))
    }
    private func playSound(start: Bool) { AudioSettings.cue(start: start) }
}
private struct LibraryPageView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: AppController
    var filtered: [HistoryEntry] { controller.history.filter { controller.historySearch.isEmpty || $0.text.localizedCaseInsensitiveContains(controller.historySearch) } }
    private var groups: [(date: Date, entries: [HistoryEntry])] {
        let grouped = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { (date: $0, entries: grouped[$0]!.sorted { $0.date > $1.date }) }
    }
    private func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.historySearchVisible { TextField("Search recordings", text: $controller.historySearch).textFieldStyle(.roundedBorder) }
            if let item = controller.selectedHistory {
                Button("‹  Back") { controller.selectedHistory = nil }.buttonStyle(.plain)
                ScrollView { Text(item.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                HStack { Text(item.date, style: .date).foregroundStyle(.secondary); Spacer(); Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id); controller.selectedHistory = nil } }
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                    if filtered.isEmpty { Text(controller.historySearch.isEmpty ? "No recordings yet" : "No recordings found").foregroundStyle(.secondary).padding(.top, 20) }
                    ForEach(groups, id: \.date) { group in
                        Text(dayLabel(group.date)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(group.entries) { item in
                            Button { controller.selectedHistory = item } label: { Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(scheme == .dark ? Color.white.opacity(0.065) : Color.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08))) }.buttonStyle(.plain)
                            .contextMenu { Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id) } }
                        }
                    }
                } }
            }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
    }
    private func copy(_ item: HistoryEntry) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string) }
}
private struct ConfigurationPageView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: AppController
    @AppStorage("theme") private var theme = "Auto"
    @AppStorage("recordingWindow") private var recordingWindow = "Classic"
    @AppStorage("alwaysShowRecording") private var alwaysShow = false
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
    @AppStorage("cancelHotkeyCode") private var cancelHotkeyCode = 53
    @AppStorage("mouseShortcut") private var mouseShortcut = -1
    @AppStorage("pushShortcutEnabled") private var pushShortcutEnabled = false
    @AppStorage("pushHotkeyCode") private var pushHotkeyCode = 49
    @AppStorage("pushHotkeyModifiers") private var pushHotkeyModifiers = Int(NSEvent.ModifierFlags.option.union(.shift).rawValue)
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("restoreClipboard") private var restoreClipboard = true
    @AppStorage("pasteResult") private var pasteResult = true
    @AppStorage("sendOnShift") private var sendOnShift = false
    @AppStorage("simulateTyping") private var simulateTyping = false
    @AppStorage("removeSilence") private var removeSilence = false
    @AppStorage("normalizeAudio") private var normalizeAudio = false
    @AppStorage("historyRetentionDays") private var retention = 0
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = false
    @AppStorage("errorLogging") private var errorLogging = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                HStack(alignment: .top) { Text("Theme").padding(.top, 16); Spacer(); choices(["Auto", "Light", "Dark"], selection: $theme, icons: ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"]) }.padding(.vertical, 12)
                Divider()
                HStack(alignment: .top) { Text("Recording window").padding(.top, 16); Spacer(); choices(["Classic", "Mini", "None"], selection: $recordingWindow, icons: ["waveform", "waveform", "eye.slash"]) }.padding(.vertical, 12)
                Divider()
                SettingsRow(title: "Always show") { Image(systemName: "questionmark.circle").help("Keep the mini recording window visible"); Toggle("", isOn: $alwaysShow).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).disabled(recordingWindow != "Mini") }
            }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }.onChange(of: alwaysShow) { _ in controller.refreshRecordingWindow() }
            Text("Keyboard Shortcuts").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                shortcutRow("Toggle Recording", subtitle: "Starts and stops recordings", key: "hotkeyCode", modifiers: "hotkeyModifiers", fallback: 49); Divider()
                shortcutRow("Cancel Recording", subtitle: "Discards the active recording", key: "cancelHotkeyCode", modifiers: nil, fallback: 53); Divider()
                shortcutRow("Push to Talk", subtitle: "Hold to record, release when done", key: "pushHotkeyCode", modifiers: "pushHotkeyModifiers", fallback: 49, enabled: "pushShortcutEnabled"); Divider()
                SettingsRow(title: "Mouse shortcut") { Picker("Mouse shortcut", selection: $mouseShortcut) { Text("Off").tag(-1); Text("Middle button").tag(2); Text("Button 4").tag(3); Text("Button 5").tag(4) }.labelsHidden().frame(width: 150) }; Divider()
                SettingsRow(title: "Use toggle shortcut for push to talk") { Toggle("", isOn: $pushToTalk).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }; Divider()
                SettingsRow(title: "Use Right Option only") { Toggle("", isOn: $rightOption).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }
            }
            Text("Application").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Update application") { Button("Check for Updates…") { controller.checkUpdates() } }; Divider()
                SettingsRow(title: "Automatically check for updates") { Toggle("", isOn: $autoCheckUpdates).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }; Divider()
                SettingsRow(title: "Launch on login") { Toggle("", isOn: $controller.loginEnabled).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).onChange(of: controller.loginEnabled) { value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { controller.loginEnabled = SMAppService.mainApp.status == .enabled; controller.message = error.localizedDescription } } }; Divider()
                SettingsRow(title: "Error logging") { Toggle("", isOn: $errorLogging).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).help("Write errors to a local log") }; Divider()
                SettingsRow(title: "Keep recordings for") { Picker("Keep recordings for", selection: retentionBinding) { Text("Forever").tag(0); Text("1 day").tag(1); Text("1 week").tag(7); Text("2 weeks").tag(14); Text("1 month").tag(30); Text("6 months").tag(180); Text("1 year").tag(365) }.labelsHidden().frame(width: 140) }; Divider()
                Button { controller.showAdvanced.toggle() } label: { HStack { Text("Advanced settings"); Spacer(); Image(systemName: controller.showAdvanced ? "chevron.down" : "chevron.right").foregroundStyle(.secondary) }.frame(minHeight: 48).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            if controller.showAdvanced {
                Text("Text input").font(.system(size: 14, weight: .semibold))
                SettingsCard {
                    SettingsRow(title: "Paste result text") { Toggle("", isOn: $pasteResult).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }; Divider()
                    SettingsRow(title: "Restore clipboard after pasting") { Toggle("", isOn: $restoreClipboard).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).disabled(!pasteResult || simulateTyping) }; Divider()
                    SettingsRow(title: "Hold Shift to auto-send") { Toggle("", isOn: $sendOnShift).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).disabled(!pasteResult) }; Divider()
                    SettingsRow(title: "Simulate keypresses") { Toggle("", isOn: $simulateTyping).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)).disabled(!pasteResult) }
                }
                Text("Audio processing").font(.system(size: 14, weight: .semibold))
                SettingsCard {
                    SettingsRow(title: "Silence removal") { Toggle("", isOn: $removeSilence).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }; Divider()
                    SettingsRow(title: "Dynamic normalization") { Toggle("", isOn: $normalizeAudio).labelsHidden().toggleStyle(.switch).tint(Color(red: 0.90, green: 0.27, blue: 0.60)) }; Divider()
                    SettingsRow(title: "Accessibility") { Button("Request Access") { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) } }
                }
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
                ZStack {
                    if values.first == "Auto" {
                        if index == 0 {
                            HStack(spacing: 0) {
                                LinearGradient(colors: [.indigo, .blue, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                                LinearGradient(colors: [.cyan, .blue, .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        } else {
                            LinearGradient(colors: index == 1 ? [.yellow.opacity(0.55), .cyan, .blue] : [.indigo, .blue, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                        VStack(spacing: 2) {
                            HStack { Spacer(); RoundedRectangle(cornerRadius: 2).fill(index == 1 ? Color.cyan.opacity(0.8) : Color.black.opacity(0.35)).frame(width: 31, height: 12) }
                            Spacer()
                            HStack { HStack(spacing: 3) { Circle().fill(.green); Circle().fill(.yellow); Circle().fill(.red); Spacer() }.frame(width: 28, height: 5).padding(5).background(index == 1 ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 5)); Spacer(minLength: 0) }
                        }.padding(3)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(scheme == .dark ? Color.black.opacity(0.36) : (selection.wrappedValue == value ? Color.blue.opacity(0.10) : Color.white))
                        if value == "None" { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
                        else { Image(systemName: "waveform").font(.system(size: value == "Mini" ? 13 : 17)).foregroundStyle(.white).frame(width: value == "Mini" ? 48 : 62, height: value == "Mini" ? 20 : 30).background(.black, in: RoundedRectangle(cornerRadius: value == "Mini" ? 10 : 6)) }
                    }
                }.frame(width: values.first == "Auto" ? 70 : 95, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.wrappedValue == value ? Color.blue : Color.primary.opacity(0.2), lineWidth: selection.wrappedValue == value ? 2 : 1))
                Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
            } }.buttonStyle(.plain)
        } }
    }
    private func shortcutRow(_ title: String, subtitle: String, key: String, modifiers: String?, fallback: Int, enabled: String? = nil) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(title); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button { if let enabled { UserDefaults.standard.set(false, forKey: enabled) } else { UserDefaults.standard.removeObject(forKey: key); if let modifiers { UserDefaults.standard.removeObject(forKey: modifiers) } }; controller.objectWillChange.send() } label: { Image(systemName: enabled == nil ? "arrow.counterclockwise" : "xmark") }.buttonStyle(.plain); ShortcutRecorder(codeKey: key, modifiersKey: modifiers, fallbackCode: fallback, enabledKey: enabled).id("\(key)-\(hotkeyCode)-\(hotkeyModifiers)-\(cancelHotkeyCode)-\(pushShortcutEnabled)-\(pushHotkeyCode)-\(pushHotkeyModifiers)").frame(width: 75, height: 28) }.frame(minHeight: 50)
    }
}
