import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement

private enum SettingsTab: String, CaseIterable {
    case sound = "Sound", models = "Models", library = "Library", configuration = "Configuration"
    var icon: String { switch self { case .sound: "speaker.wave.2.fill"; case .models: "book"; case .library: "clock.arrow.circlepath"; case .configuration: "gearshape" } }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @AppStorage("theme") private var theme = "Auto"
    @Environment(\.colorScheme) private var scheme
    private var effectiveTheme: String { ProcessInfo.processInfo.environment["LIGHTTTS_SCREENSHOT_APPEARANCE"] ?? theme }
    private var dark: Bool { effectiveTheme == "Dark" || (effectiveTheme == "Auto" && scheme == .dark) }
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
            }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 185).frame(maxHeight: .infinity).background(Color(nsColor: dark ? NSColor(srgbRed: 59/255, green: 62/255, blue: 69/255, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                HStack {
                    if controller.settingsSelection == "Library" {
                        Button { if controller.selectedHistory != nil { controller.stopHistoryPlayback(); controller.selectedHistory = nil } else { controller.settingsSelection = "Sound" } } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.buttonStyle(.plain)
                    }
                    if let item = controller.selectedHistory, controller.settingsSelection == "Library" { Spacer(); Text(item.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_US")))).font(.system(size: 14, weight: .bold)); Spacer() }
                    else { Text(controller.settingsSelection).font(.system(size: 14, weight: .bold)); Spacer() }
                    if controller.settingsSelection == "Library" {
                        if controller.selectedHistory != nil { Color.clear.frame(width: 28, height: 28) }
                        else if controller.historySearchVisible {
                            HStack(spacing: 6) { Image(systemName: "magnifyingglass"); TextField("Search history", text: $controller.historySearch).textFieldStyle(.plain); Button { controller.historySearch = ""; controller.historySearchVisible = false } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }.padding(.horizontal, 9).frame(width: 220, height: 28).background(Color.primary.opacity(0.09), in: Capsule())
                        } else { Button { controller.historySearchVisible.toggle() } label: { Image(systemName: "magnifyingglass").frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()) }.buttonStyle(.plain).help("Search recordings") }
                    } else {
                        Menu { Button("System Default") { UserDefaults.standard.set("", forKey: "inputDevice") }; Divider(); ForEach(AVCaptureDevice.devices(for: .audio), id: \.uniqueID) { device in Button(device.localizedName) { UserDefaults.standard.set(device.uniqueID, forKey: "inputDevice") } } } label: { Image(systemName: "laptopcomputer").font(.system(size: 14)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).background(Color.primary.opacity(0.09), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.1))).help("Select microphone")
                    }
                }.padding(.horizontal, 16).frame(height: 48)
                switch controller.settingsSelection {
                case "Sound": SoundPageView(controller: controller)
                case "Models": ModelsPageView()
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: dark ? NSColor(srgbRed: 44/255, green: 47/255, blue: 52/255, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
        }.frame(width: 750, height: 508).foregroundStyle(dark ? Color(red: 233/255, green: 233/255, blue: 234/255) : Color(nsColor: .labelColor)).preferredColorScheme(effectiveTheme == "Dark" ? .dark : effectiveTheme == "Light" ? .light : nil)
    }
}

struct ModelsPageView: View { var body: some View { Spacer() } }

private struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { content }.padding(.horizontal, 16).background(scheme == .dark ? Color(red: 60/255, green: 63/255, blue: 67/255) : Color(white: 253/255), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.08))) }
}
private struct SettingsRow<Content: View>: View {
    let title: String
    var help: String? = nil
    @ViewBuilder var content: Content
    var body: some View { HStack(spacing: 8) { Text(title); if let help { Image(systemName: "info.circle").help(help) }; Spacer(); content }.frame(minHeight: 48) }
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
                SettingsRow(title: "Sound effects") { HStack(spacing: 0) { ForEach(["Simple", "Classic", "Off"], id: \.self) { value in Button { sound = value } label: { Text(value).font(.system(size: 14, weight: sound == value ? .semibold : .regular)).frame(maxWidth: .infinity).frame(height: 26).foregroundStyle(sound == value ? (scheme == .dark ? Color.white : Color.black) : Color.secondary).background(sound == value ? (scheme == .dark ? Color(red: 91/255, green: 93/255, blue: 99/255) : Color.white) : Color.clear, in: RoundedRectangle(cornerRadius: 7)) }.buttonStyle(.plain) } }.padding(2).frame(width: 168).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1))) }
                Divider()
                SettingsRow(title: "Volume") { Button { playSound(start: true) } label: { Image(systemName: "speaker.fill") }.buttonStyle(.plain); SoundVolumeSlider(value: $volume, dark: scheme == .dark); Button { playSound(start: false) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain) }
            }
            Text("Recording").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Sound while recording") {
                    Menu {
                        ForEach(["Keep Playing", "Pause", "Mute", "Lower", "Muffle"], id: \.self) { value in Button(value) { recordingSound = value } }
                    } label: {
                        HStack(spacing: 8) { Image(systemName: recordingSound == "Pause" ? "pause.circle" : recordingSound == "Mute" ? "speaker.slash" : "speaker.wave.2"); Text(recordingSound); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }.padding(.horizontal, 9)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 145, height: 30).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1))).overlay(alignment: .trailing) { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 9).allowsHitTesting(false) }.help("Pause uses the system media control; Muffle lowers volume if system audio capture is unavailable.")
                }
                Divider()
                HStack { Text("Automatically increase microphone volume"); Image(systemName: "questionmark.circle").help("Increase input volume while recording"); Spacer(); Toggle("", isOn: $increaseMic).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)) }.frame(minHeight: 48)
            }
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.top, 16) }.font(.system(size: 14))
    }
    private func playSound(start: Bool) { AudioSettings.cue(start: start) }
}
private struct SoundVolumeSlider: View {
    @Binding var value: Double
    let dark: Bool
    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(1, geometry.size.width - 20)
            ZStack(alignment: .leading) {
                Capsule().fill(dark ? Color(white: 0.40) : Color(white: 0.86)).frame(width: trackWidth, height: 6).offset(x: 10)
                if !dark { Capsule().fill(Color(red: 228/255, green: 92/255, blue: 156/255)).frame(width: max(0, trackWidth * value), height: 6).offset(x: 10) }
                HStack { ForEach(0..<9) { index in Circle().fill(Color.primary.opacity(0.16)).frame(width: 2, height: 2); if index < 8 { Spacer() } } }.padding(.horizontal, 10).offset(y: 12)
                Circle().fill(dark ? Color(white: 0.88) : Color.white).frame(width: 20, height: 20).shadow(color: .black.opacity(0.12), radius: 1, y: 1).offset(x: trackWidth * value)
            }.frame(maxHeight: .infinity).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { point in value = min(1, max(0, (point.location.x - 10) / trackWidth)) })
        }.frame(width: 202, height: 28).accessibilityElement().accessibilityLabel("Volume").accessibilityValue("\(Int(value * 100)) percent").accessibilityAdjustableAction { direction in if direction == .increment { value = min(1, value + 0.05) } else if direction == .decrement { value = max(0, value - 0.05) } }
    }
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
            if let item = controller.selectedHistory {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView { VStack(alignment: .leading, spacing: 12) {
                        Text(item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(scheme == .dark ? Color(red: 60/255, green: 63/255, blue: 67/255) : Color(white: 253/255), in: RoundedRectangle(cornerRadius: 16))
                        HStack { Button { controller.toggleHistoryPlayback(item) } label: { Image(systemName: controller.playingHistoryID == item.id ? "pause.fill" : "play.fill") }.buttonStyle(.plain).disabled(controller.historyAudioURL(item) == nil); HStack(spacing: 1) { if let waveform = item.waveform, !waveform.isEmpty { ForEach(Array(waveform.enumerated()), id: \.offset) { _, amplitude in Capsule().fill(Color.primary.opacity(0.65)).frame(width: 1, height: max(2, CGFloat(amplitude) * 20)) } } else { Image(systemName: "waveform").foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, minHeight: 24); Text(item.recordingDuration.map { String(format: "%.1fs", $0) } ?? "—").foregroundStyle(.secondary).font(.caption) }.padding(10).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                        HStack {
                            Button("Original") { controller.historySegmented = false }.buttonStyle(.plain).padding(6).background(!controller.historySegmented ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            Button("Segmented") { controller.historySegmented = true }.buttonStyle(.plain).padding(6).background(controller.historySegmented ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5)).disabled(item.segments?.isEmpty ?? true).help("Play speech segments detected from the recording")
                        }.font(.caption)
                        if controller.historySegmented, let segments = item.segments {
                            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in Button { controller.toggleHistoryPlayback(item, segment: segment) } label: { HStack { Image(systemName: "play.fill"); Text("Segment \(index + 1)"); Spacer(); Text(String(format: "%.1fs – %.1fs", segment.start, segment.end)).foregroundStyle(.secondary) }.font(.caption).padding(10).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain) }
                        }
                    } }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
                    VStack(spacing: 12) {
                        SettingsCard { SettingsRow(title: "Mode") { Text(item.mode ?? "Not available").lineLimit(1).foregroundStyle(.secondary) } }
                        SettingsCard {
                            SettingsRow(title: "Input") { Text(item.inputName ?? "Not available").lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary); Text(item.recordingDuration.map { String(format: "%.1fs", $0) } ?? "—").font(.caption).foregroundStyle(.secondary) }; Divider()
                            SettingsRow(title: "Voice model") { Text(item.modelName ?? "Not available").lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary); Text(item.processingDuration.map { String(format: "%.0fms", $0 * 1000) } ?? "—").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        HStack(spacing: 6) { Button("Report issue") { NSWorkspace.shared.open(URL(string: "https://github.com/imraghavojha/lighttts/issues/new")!) }; Button("Open file location") { controller.revealHistory(item) } }.controlSize(.small)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Spacer(); HStack { Spacer(); Text(controller.historySearch.isEmpty ? "No recordings yet" : "No recordings found.").foregroundStyle(.secondary); Spacer() }; Spacer()
            } else {
                ScrollView { LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(groups, id: \.date) { group in
                        Text(dayLabel(group.date)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(group.entries) { item in
                            HStack(spacing: 8) {
                                Button { controller.historySegmented = false; controller.selectedHistory = item } label: { Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                                if controller.hoveredHistoryID == item.id { Menu { Button("Copy") { copy(item) }; Button("Delete", role: .destructive) { controller.deleteHistory(item.id) } } label: { Image(systemName: "ellipsis").font(.system(size: 14)) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize() }
                            }.padding(16).background(scheme == .dark ? Color(red: 60/255, green: 63/255, blue: 67/255) : Color(white: 253/255), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08))).onHover { controller.hoveredHistoryID = $0 ? item.id : nil }
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
                HStack(alignment: .top) { Text("Theme").padding(.top, 16); Spacer(); choices(["Auto", "Light", "Dark"], selection: $theme, icons: ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"]) }.padding(.vertical, 8)
                Divider()
                HStack(alignment: .top) { Text("Recording window").padding(.top, 16); Spacer(); choices(["Classic", "Mini", "None"], selection: $recordingWindow, icons: ["waveform", "waveform", "eye.slash"]) }.padding(.vertical, 8)
                Divider()
                HStack(spacing: 8) { Text("Always show"); Image(systemName: "questionmark.circle").help("Keep the mini recording window visible"); Spacer(); Toggle("", isOn: $alwaysShow).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).disabled(recordingWindow != "Mini") }.frame(height: 45)
            }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }.onChange(of: alwaysShow) { _ in controller.refreshRecordingWindow() }
            Text("Keyboard Shortcuts").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                shortcutRow("Toggle Recording", subtitle: "Starts and stops recordings", key: "hotkeyCode", modifiers: "hotkeyModifiers", fallback: 49); Divider()
                shortcutRow("Cancel Recording", subtitle: "Discards the active recording", key: "cancelHotkeyCode", modifiers: nil, fallback: 53); Divider()
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Change mode"); Text("Activates the mode switcher").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.counterclockwise"); keycap("⌥"); keycap("⇧"); keycap("K") }.frame(minHeight: 50).foregroundStyle(.secondary).help("Modes are not included in LightTTS"); Divider()
                shortcutRow("Push to Talk", subtitle: "Hold to record, release when done", key: "pushHotkeyCode", modifiers: "pushHotkeyModifiers", fallback: 49, enabled: "pushShortcutEnabled"); Divider()
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Mouse shortcut"); Text("Tap to toggle, or hold and release when done").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); MouseShortcutRecorder().frame(width: 120, height: 28) }.frame(minHeight: 50)
            }
            Text("Application").font(.system(size: 14, weight: .semibold))
            SettingsCard {
                SettingsRow(title: "Update application") { Button("Check for Updates…") { controller.checkUpdates() } }; Divider()
                SettingsRow(title: "Automatically check for updates", help: "Check for new releases automatically") { Toggle("", isOn: $autoCheckUpdates).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)) }; Divider()
                SettingsRow(title: "Launch on login", help: "Open LightTTS when you log in") { Toggle("", isOn: $controller.loginEnabled).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).onChange(of: controller.loginEnabled) { value in do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { controller.loginEnabled = SMAppService.mainApp.status == .enabled; controller.message = error.localizedDescription } } }; Divider()
                SettingsRow(title: "Error logging", help: "Write diagnostic errors to a local log") { Toggle("", isOn: $errorLogging).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).help("Write errors to a local log") }; Divider()
                SettingsRow(title: "Keep recordings for", help: "Automatically remove older recordings") { Picker("Keep recordings for", selection: retentionBinding) { Text("Forever").tag(0); Text("1 day").tag(1); Text("1 week").tag(7); Text("2 weeks").tag(14); Text("1 month").tag(30); Text("6 months").tag(180); Text("1 year").tag(365) }.labelsHidden().frame(width: 140) }
            }
            SettingsCard { Button { controller.showAdvanced.toggle() } label: { HStack { Text("Advanced settings"); Spacer(); Image(systemName: controller.showAdvanced ? "chevron.down" : "chevron.right").foregroundStyle(.secondary) }.frame(height: 48).contentShape(Rectangle()) }.buttonStyle(.plain) }
            if controller.showAdvanced {
                Text("Text input").font(.system(size: 14, weight: .semibold))
                SettingsCard {
                    SettingsRow(title: "Paste result text") { Toggle("", isOn: $pasteResult).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)) }; Divider()
                    SettingsRow(title: "Restore clipboard after pasting") { Toggle("", isOn: $restoreClipboard).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).disabled(!pasteResult || simulateTyping) }; Divider()
                    SettingsRow(title: "Hold Shift to auto-send") { Toggle("", isOn: $sendOnShift).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).disabled(!pasteResult) }; Divider()
                    SettingsRow(title: "Simulate keypresses") { Toggle("", isOn: $simulateTyping).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)).disabled(!pasteResult) }
                }
                Text("Audio processing").font(.system(size: 14, weight: .semibold))
                SettingsCard {
                    SettingsRow(title: "Silence removal") { Toggle("", isOn: $removeSilence).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)) }; Divider()
                    SettingsRow(title: "Dynamic normalization") { Toggle("", isOn: $normalizeAudio).labelsHidden().toggleStyle(.switch).tint(Color(red: 228/255, green: 92/255, blue: 156/255)) }; Divider()
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
                                LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.30), Color(red: 0.03, green: 0.20, blue: 0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                                LinearGradient(colors: [Color(white: 0.86), Color(red: 0.55, green: 0.79, blue: 0.92), Color(red: 0.12, green: 0.35, blue: 0.70)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            }
                        } else {
                            LinearGradient(colors: index == 1 ? [Color(white: 0.86), Color(red: 0.55, green: 0.79, blue: 0.92), Color(red: 0.12, green: 0.35, blue: 0.70)] : [Color(red: 0.10, green: 0.06, blue: 0.30), Color(red: 0.03, green: 0.20, blue: 0.55), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                        if index == 0 {
                            HStack(spacing: 2) { ForEach(0..<2) { side in VStack(spacing: 1) { RoundedRectangle(cornerRadius: 2).fill(side == 0 ? Color.black.opacity(0.35) : Color.cyan.opacity(0.65)).frame(height: 11); Spacer(); HStack(spacing: 2) { Circle().fill(.yellow); Circle().fill(.pink); Spacer(minLength: 0) }.frame(height: 5).padding(3).background(side == 0 ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 5)) } } }.padding(3)
                        } else {
                            VStack(spacing: 2) {
                                HStack { Spacer(); RoundedRectangle(cornerRadius: 2).fill(index == 1 ? Color.cyan.opacity(0.8) : Color.black.opacity(0.4)).frame(width: 31, height: 12) }
                                Spacer()
                                HStack { HStack(spacing: 3) { Circle().fill(.green); Circle().fill(.yellow); Circle().fill(.red); Spacer() }.frame(width: 28, height: 5).padding(5).background(index == 1 ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 5)); Spacer(minLength: 0) }
                            }.padding(3)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(scheme == .dark ? Color.black.opacity(0.36) : (selection.wrappedValue == value ? Color.blue.opacity(0.10) : Color.white))
                        if value == "None" { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
                        else if value == "Classic" {
                            VStack(spacing: 2) {
                                HStack(spacing: 1) { ForEach(0..<25) { index in Capsule().fill(.white).frame(width: 1, height: CGFloat(3 + ((index * 7) % 12))) } }.frame(height: 16)
                                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.25)).frame(width: 56, height: 6)
                            }.frame(width: 62, height: 30).background(.black, in: RoundedRectangle(cornerRadius: 6))
                        } else { Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(.white).frame(width: 48, height: 20).background(.black, in: Capsule()) }
                    }
                }.frame(width: values.first == "Auto" ? 70 : 95, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(selection.wrappedValue == value ? Color(red: 69/255, green: 151/255, blue: 247/255) : Color.primary.opacity(0.2), lineWidth: selection.wrappedValue == value ? 2 : 1))
                Text(value).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
            } }.buttonStyle(.plain)
        } }
    }
    private func keyLabel(_ code: Int) -> String { let letters = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"]; return code == 49 ? "Space" : code == 53 ? "esc" : (letters[code] ?? "Key \(code)") }
    private func keycap(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 6).padding(.vertical, 4).background(Color.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: 4)) }
    private func shortcutRow(_ title: String, subtitle: String, key: String, modifiers: String?, fallback: Int, enabled: String? = nil) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(title); Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button { if let enabled { UserDefaults.standard.set(false, forKey: enabled) } else { UserDefaults.standard.removeObject(forKey: key); if let modifiers { UserDefaults.standard.removeObject(forKey: modifiers) } }; controller.objectWillChange.send() } label: { Image(systemName: enabled == nil ? "arrow.counterclockwise" : "xmark") }.buttonStyle(.plain); ZStack { HStack(spacing: 4) { if let enabled, !UserDefaults.standard.bool(forKey: enabled) { Text("Record shortcut").font(.system(size: 11)).foregroundStyle(.secondary) } else { let raw = modifiers == "pushHotkeyModifiers" ? pushHotkeyModifiers : (modifiers == nil ? 0 : hotkeyModifiers); let flags = NSEvent.ModifierFlags(rawValue: UInt(raw)); if flags.contains(.control) { keycap("⌃") }; if flags.contains(.option) { keycap("⌥") }; if flags.contains(.shift) { keycap("⇧") }; if flags.contains(.command) { keycap("⌘") }; let code = key == "cancelHotkeyCode" ? cancelHotkeyCode : (key == "pushHotkeyCode" ? pushHotkeyCode : hotkeyCode); keycap(keyLabel(code)) } }; ShortcutRecorder(codeKey: key, modifiersKey: modifiers, fallbackCode: fallback, enabledKey: enabled).opacity(0.015) }.id("\(key)-\(hotkeyCode)-\(hotkeyModifiers)-\(cancelHotkeyCode)-\(pushShortcutEnabled)-\(pushHotkeyCode)-\(pushHotkeyModifiers)").frame(minWidth: 60, maxWidth: 120, minHeight: 28) }.frame(minHeight: 50)
    }
}
