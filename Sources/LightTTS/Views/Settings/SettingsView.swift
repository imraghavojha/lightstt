import SwiftUI
import AppKit
import AVFoundation
import ApplicationServices
import ServiceManagement
import LightTTSCore

private final class SettingsDialogState: ObservableObject { @Published var deleting: Model? }

private enum SettingsTab: String, CaseIterable {
    case sound = "Sound", models = "Models", library = "Library", configuration = "Configuration"
    var icon: String { switch self { case .sound: "speaker.wave.2.fill"; case .models: "book.fill"; case .library: "clock.arrow.circlepath"; case .configuration: "gearshape" } }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @StateObject private var dialog = SettingsDialogState()
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("theme") private var theme = "Auto"
    @Environment(\.colorScheme) private var scheme
    private var effectiveTheme: String { ProcessInfo.processInfo.environment["LIGHTTTS_SCREENSHOT_APPEARANCE"] ?? theme }
    private var dark: Bool { effectiveTheme == "Dark" || (effectiveTheme == "Auto" && scheme == .dark) }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    Button { controller.selectSettings(tab.rawValue) } label: {
                        HStack(spacing: 5) {
                            Group { if tab == .configuration { ConfigurationGlyph() } else { Image(systemName: tab.icon).font(.system(size: 12, weight: .semibold)) } }.foregroundStyle(.white).frame(width: 20, height: 20).background(Color(white: 0.32).gradient, in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.12), lineWidth: 0.5)).shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                            Text(tab.rawValue).font(.system(size: 13, weight: .medium))
                            Spacer()
                        }.padding(.horizontal, 8).frame(height: 35).background(controller.settingsSelection == tab.rawValue ? (dark ? Color.white.opacity(0.16) : Color.white.opacity(0.65)) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button(attached ? "Detach into window" : "Back to menu", action: detach).buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12)).padding(8)
            }.padding(.horizontal, 12).padding(.top, 58).padding(.bottom, 12).frame(width: 184).frame(maxHeight: .infinity).background(Color(nsColor: dark ? NSColor(srgbRed: 58/255, green: 62/255, blue: 69/255, alpha: 1) : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.91, alpha: 1)))
            Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1)
            VStack(spacing: 0) {
                if controller.settingsSelection != "Models" && controller.settingsSelection != "Library" && !(controller.settingsSelection == "Configuration" && controller.showAdvanced) {
                    HStack {
                        Text(controller.settingsSelection).font(.system(size: 13, weight: .bold)); Spacer()
                        Menu { Button("System Default") { SettingsDefaults.store.set("", forKey: "inputDeviceUID") }; Divider(); ForEach(AVCaptureDevice.devices(for: .audio), id: \.uniqueID) { device in Button(device.localizedName) { SettingsDefaults.store.set(device.uniqueID, forKey: "inputDeviceUID") } } } label: { Image(systemName: "laptopcomputer").font(.system(size: 14)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).background(LinearGradient(colors: dark ? [Color(white: 0.29), Color(white: 0.22)] : [Color(white: 0.99), Color(white: 0.92)], startPoint: .top, endPoint: .bottom), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 0.5)).offset(x: 6).help("Select microphone")
                    }.padding(.horizontal, 16).frame(height: 48)
                }
                switch controller.settingsSelection {
                case "Sound": SoundPageView(controller: controller)
                case "Models": ModelsPageView(controller: controller, deleting: $dialog.deleting)
                case "Library": LibraryPageView(controller: controller)
                default: ConfigurationPageView(controller: controller)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(nsColor: dark ? NSColor(srgbRed: 43/255, green: 48/255, blue: 53/255, alpha: 1) : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)))
        }.frame(width: 750, height: 508).foregroundStyle(dark ? Color(red: 233/255, green: 233/255, blue: 234/255) : Color(white: 0.30)).preferredColorScheme(effectiveTheme == "Dark" ? .dark : effectiveTheme == "Light" ? .light : nil).defaultAppStorage(CommandLine.arguments.contains("--ui-fixture") ? SettingsDefaults.store : .standard)
        .background(ConfirmationFrameOverlay(model: dialog.deleting, name: dialog.deleting?.name ?? "", cancel: { dialog.deleting = nil }, delete: { model in
            do { try controller.deleteModel(model) } catch { controller.message = error.localizedDescription }; dialog.deleting = nil
        }))
        .onChange(of: selectedModel) { _ in controller.reloadSelectedModel() }
    }
}

private struct ConfigurationGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for index in 0..<16 {
                let angle = Double(index) * .pi / 8
                var mark = Path()
                mark.move(to: CGPoint(x: center.x + cos(angle) * 5, y: center.y + sin(angle) * 5))
                mark.addLine(to: CGPoint(x: center.x + cos(angle) * 7, y: center.y + sin(angle) * 7))
                context.stroke(mark, with: .color(.white), lineWidth: 0.8)
            }
            let ring = CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)
            context.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 1)
        }.frame(width: 16, height: 16)
    }
}



private struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View { VStack(spacing: 0) { content }.padding(.horizontal, 16).background(scheme == .dark ? Color(red: 58/255, green: 63/255, blue: 68/255) : Color(white: 253/255), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(LinearGradient(colors: scheme == .dark ? [Color(red: 77/255, green: 78/255, blue: 83/255), Color(red: 55/255, green: 57/255, blue: 62/255)] : [Color.white, Color.black.opacity(0.09)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5)) }
}
private struct ReferenceSwitchStyle: ToggleStyle {
    let label: String
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule().fill(configuration.isOn ? Color(red: 246/255, green: 79/255, blue: 158/255) : Color.primary.opacity(0.16))
                .overlay(Circle().fill(Color.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.18), radius: 1, y: 1).offset(x: configuration.isOn ? 7 : -7))
                .frame(width: 34, height: 20).opacity(enabled ? 1 : 0.5)
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
private struct SettingsRow<Content: View>: View {
    let title: String
    var help: String? = nil
    var height: CGFloat = 48
    var contentOffset: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View { HStack(spacing: 8) { Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false); if let help { Image(systemName: "info.circle").help(help) }; Spacer(); content }.offset(y: contentOffset).frame(minHeight: height) }
}
private struct SoundPageView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var scheme
    @AppStorage("soundEffects") private var sound = "Classic"
    @AppStorage("soundVolume") private var volume = 0.8
    @AppStorage("recordingSound") private var recordingSound = "Pause"
    @AppStorage("increaseMicVolume") private var increaseMic = false
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                SettingsRow(title: "Sound effects", height: 54) { HStack(spacing: 0) { ForEach(["Simple", "Classic", "Off"], id: \.self) { value in Button { sound = value } label: { Text(value).font(.system(size: 12, weight: sound == value ? .semibold : .regular)).frame(width: value == "Classic" ? 62 : value == "Simple" ? 62 : 40, height: 24).foregroundStyle(sound == value ? (scheme == .dark ? Color.white : Color.black) : Color.secondary).background(sound == value ? (scheme == .dark ? Color(red: 91/255, green: 93/255, blue: 99/255) : Color.white) : Color.clear, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(sound == value ? Color.primary.opacity(0.12) : .clear, lineWidth: 0.5)).shadow(color: sound == value ? .black.opacity(0.12) : .clear, radius: 1, y: 0.5) }.buttonStyle(.plain) } }.padding(2).background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1))) }
                PageRule()
                SettingsRow(title: "Volume", height: 46) { Button { playSound(start: true) } label: { Image(systemName: "speaker.fill") }.buttonStyle(.plain); SoundVolumeSlider(value: $volume, dark: scheme == .dark); Button { playSound(start: false) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain) }
            }
            Text("Recording").font(.system(size: 13, weight: .semibold)).padding(.top, 18).padding(.bottom, 8.5)
            SettingsCard {
                SettingsRow(title: "Sound while recording", contentOffset: 5) {
                    Menu {
                        ForEach(["Keep Playing", "Pause", "Mute", "Lower", "Muffle"], id: \.self) { value in Button(value == "Pause" ? "Pause (Unavailable)" : value) { recordingSound = value }.disabled(value == "Pause") }
                    } label: {
                        HStack(spacing: 8) { Image(systemName: recordingSound == "Pause" ? "pause.circle" : recordingSound == "Mute" ? "speaker.slash" : "speaker.wave.2"); Text(recordingSound); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }.padding(.horizontal, 9)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 145, height: 30).background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.1))).overlay(alignment: .trailing) { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 9).allowsHitTesting(false) }.help("Pause is unavailable and leaves playback unchanged; Muffle lowers volume if system audio capture is unavailable.")
                }
                PageRule()
                HStack { Text("Automatically increase microphone volume"); Image(systemName: "questionmark.circle").help("Increase input volume while recording"); Spacer(); Toggle("", isOn: $increaseMic).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Automatically increase microphone volume")) }.offset(y: -2).frame(minHeight: 44)
            }
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).padding(.top, 16) }.font(.system(size: 13))
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
                if !dark { Capsule().fill(Color(red: 246/255, green: 79/255, blue: 158/255)).frame(width: max(0, trackWidth * value), height: 6).offset(x: 10) }
                HStack { ForEach(0..<9) { index in Circle().fill(Color.primary.opacity(0.16)).frame(width: 2, height: 2); if index < 8 { Spacer() } } }.padding(.horizontal, 10).offset(y: 7)
                Capsule().fill(dark ? Color(white: 0.88) : Color.white).frame(width: 20, height: 16).shadow(color: .black.opacity(0.12), radius: 1, y: 1).offset(x: trackWidth * value)
            }.frame(maxHeight: .infinity).contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { point in value = min(1, max(0, (point.location.x - 10) / trackWidth)) })
        }.frame(width: 211, height: 28).accessibilityElement().accessibilityLabel("Volume").accessibilityValue("\(Int(value * 100)) percent").accessibilityAdjustableAction { direction in if direction == .increment { value = min(1, value + 0.05) } else if direction == .decrement { value = max(0, value - 0.05) } }
    }
}
private struct ConfigurationPageView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var controller: AppController
    @AppStorage("theme") private var theme = "Auto"
    @AppStorage("recordingWindow") private var recordingWindow = "Classic"
    @AppStorage("alwaysShowRecordingWindow") private var alwaysShow = false
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
    @AppStorage("autoPaste") private var pasteResult = true
    @AppStorage("sendOnShift") private var sendOnShift = false
    @AppStorage("simulateTyping") private var simulateTyping = false
    @AppStorage("removeSilence") private var removeSilence = false
    @AppStorage("normalizeAudio") private var normalizeAudio = false
    @AppStorage("historyRetentionDays") private var retention = 0
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = false
    var body: some View {
        Group { if controller.showAdvanced { advancedPage } else { configurationPage } }
            .onAppear { controller.refreshLoginStatus() }
            .onDisappear { controller.showAdvanced = false }
    }
    private var configurationPage: some View {
        ScrollView { VStack(alignment: .leading, spacing: 0) {
            SettingsCard {
                HStack(alignment: .top) { Text("Theme").padding(.top, 2); Spacer(); choices(["Auto", "Light", "Dark"], selection: $theme, icons: ["circle.lefthalf.filled", "sun.max.fill", "moon.fill"]) }.padding(.top, 12).padding(.bottom, 4)
                PageRule()
                HStack(alignment: .top) { Text("Recording window").padding(.top, 1); Spacer(); choices(["Classic", "Mini", "None"], selection: $recordingWindow, icons: ["waveform", "waveform", "eye.slash"]).padding(.trailing, 4) }.padding(.top, 12).padding(.bottom, 10)
                PageRule()
                HStack(spacing: 8) { Text("Always show"); Image(systemName: "questionmark.circle").help("Keep the mini recording window visible"); Spacer(); Toggle("", isOn: $alwaysShow).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Always show")).disabled(recordingWindow != "Mini") }.frame(height: 45)
            }.onChange(of: recordingWindow) { _ in controller.refreshRecordingWindow() }.onChange(of: alwaysShow) { _ in controller.refreshRecordingWindow() }
            Text("Keyboard Shortcuts").font(.system(size: 13, weight: .medium)).padding(.top, 18).padding(.bottom, 9)
            SettingsCard {
                shortcutRow("Toggle Recording", subtitle: "Starts and stops recordings", key: "hotkeyCode", modifiers: "hotkeyModifiers", fallback: 49); PageRule()
                shortcutRow("Cancel Recording", subtitle: "Discards the active recording", key: "cancelHotkeyCode", modifiers: nil, fallback: 53); PageRule()
                HStack(spacing: 4) { VStack(alignment: .leading, spacing: 2) { Text("Change mode"); Text("Activates the mode switcher").font(.system(size: 10)).foregroundStyle(scheme == .dark ? Color(red: 217/255, green: 218/255, blue: 222/255) : Color(white: 93/255)) }; Spacer(); Image(systemName: "arrow.counterclockwise").font(.system(size: 10)).foregroundStyle(.secondary).padding(.trailing, 4); keycap("⌥"); keycap("⇧"); keycap("K") }.padding(.trailing, 6).frame(minHeight: 50).help("Modes are not included in LightTTS"); PageRule()
                shortcutRow("Push to Talk", subtitle: "Hold to record, release when done", key: "pushHotkeyCode", modifiers: "pushHotkeyModifiers", fallback: 49, enabled: "pushShortcutEnabled"); PageRule()
                HStack { VStack(alignment: .leading, spacing: 2) { Text("Mouse shortcut"); Text("Tap to toggle, or hold and release when done").font(.system(size: 10)).foregroundStyle(scheme == .dark ? Color(red: 217/255, green: 218/255, blue: 222/255) : Color(white: 93/255)) }; Spacer(); MouseShortcutRecorder().frame(width: 120, height: 28) }.frame(minHeight: 50)
            }
            Text("Application").font(.system(size: 13, weight: .semibold)).padding(.top, 18).padding(.bottom, 9)
            SettingsCard {
                ConfigurationApplicationRow(title: "Update application") { Button("Check for Updates…") { controller.checkUpdates() } }; PageRule()
                ConfigurationApplicationRow(title: "Automatically check for updates", help: "Check for new releases automatically") { Toggle("", isOn: $autoCheckUpdates).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Automatically check for updates")) }; PageRule()
                ConfigurationApplicationRow(title: "Launch on login", help: "Open LightTTS when you log in") { Toggle("", isOn: Binding(get: { controller.loginEnabled }, set: { controller.setLoginEnabled($0) })).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Launch on login")) }; PageRule()
                ConfigurationApplicationRow(title: "Keep recordings for", help: "Automatically remove older recordings") { RetentionPopup(selection: retentionBinding) }
            }
            SettingsCard { Button { controller.showAdvanced.toggle() } label: { HStack { Text("Advanced settings"); Spacer(); Image(systemName: controller.showAdvanced ? "chevron.down" : "chevron.right").foregroundStyle(.secondary) }.frame(height: 48).contentShape(Rectangle()) }.buttonStyle(.plain) }.padding(.top, 18)
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24) }.font(.system(size: 13))
    }
    private var advancedPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { controller.showAdvanced = false } label: { Image(systemName: "chevron.left").frame(width: 28, height: 28).background(LinearGradient(colors: scheme == .dark ? [Color(white: 0.29), Color(white: 0.22)] : [Color(white: 0.99), Color(white: 0.92)], startPoint: .top, endPoint: .bottom), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.16), lineWidth: 0.5)) }.buttonStyle(.plain).help("Back to Configuration")
                Text("Advanced settings").font(.system(size: 13, weight: .bold)); Spacer()
            }.padding(.horizontal, 12).frame(height: 48)
            ScrollView { VStack(alignment: .leading, spacing: 0) {
                advancedHeading("Application")
                SettingsCard {
                    unavailableRow("Show in Dock"); PageRule()
                    unavailableRow("Start Recording on Menubar Click"); PageRule()
                    unavailableRow("Close after transcription")
                }
                advancedHeading("Voice model")
                SettingsCard { ConfigurationApplicationRow(title: "Voice model active duration", help: "Voice model lifetime is managed automatically") { Text("Automatic").foregroundStyle(.secondary) } }
                advancedHeading("Audio processing")
                SettingsCard {
                    ConfigurationApplicationRow(title: "Silence removal", help: "Remove silence from recordings") { Toggle("", isOn: $removeSilence).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Silence removal")) }; PageRule()
                    ConfigurationApplicationRow(title: "Dynamic normalization", help: "Normalize recording volume") { Toggle("", isOn: $normalizeAudio).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Dynamic normalization")) }
                }
                advancedHeading("App folder location")
                SettingsCard { ConfigurationApplicationRow(title: "App folder location") { Text("Managed by LightTTS").foregroundStyle(.secondary) } }
                advancedHeading("Text input")
                SettingsCard {
                    ConfigurationApplicationRow(title: "Clipboard content", help: "Choose whether to restore the previous clipboard contents") {
                        SettingsPopup(selection: Binding(get: { restoreClipboard ? 1 : 0 }, set: { restoreClipboard = $0 == 1 }), options: ["Keep result", "Restore previous"], width: 145).frame(width: 145, height: 28)
                    }; PageRule()
                    unavailableRow("Clipboard history"); PageRule()
                    ConfigurationApplicationRow(title: "Paste result text", help: "Paste the transcription into the focused app") { Toggle("", isOn: $pasteResult).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Paste result text")) }; PageRule()
                    ConfigurationApplicationRow(title: "Hold shift to auto-send after paste", help: "Send Return when Shift is held") { Toggle("", isOn: $sendOnShift).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Hold shift to auto-send after paste")) }; PageRule()
                    ConfigurationApplicationRow(title: "Simulate keypresses", help: "Type the result instead of pasting it") { Toggle("", isOn: $simulateTyping).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: "Simulate keypresses")) }
                }
            }.padding(.horizontal, 24).padding(.bottom, 24).environment(\.advancedSettingsRows, true) }.font(.system(size: 13))
        }
    }
    private func advancedHeading(_ title: String) -> some View { Text(title).font(.system(size: 13, weight: .semibold)).padding(.top, title == "Application" ? 14 : 22).padding(.bottom, 9) }
    private func unavailableRow(_ title: String) -> some View {
        ConfigurationApplicationRow(title: title, help: "Not available in LightTTS") { Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(ReferenceSwitchStyle(label: title)).disabled(true) }
    }
    private var retentionLabel: String { [0: "Forever", 1: "1 day", 7: "1 week", 14: "2 weeks", 30: "1 month", 180: "6 months", 365: "1 year"][retention] ?? "Forever" }
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
        HStack(spacing: values.first == "Auto" ? 15 : 16) { ForEach(Array(values.enumerated()), id: \.offset) { index, value in
            Button { selection.wrappedValue = value } label: { VStack(spacing: values.first == "Auto" ? 8 : 5) {
                ZStack {
                    if values.first == "Auto" {
                        ThemeArtwork(mode: index)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(scheme == .dark ? Color.black.opacity(0.36) : (selection.wrappedValue == value ? Color.blue.opacity(0.10) : Color.white))
                        if value == "None" { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
                        else if value == "Classic" {
                            VStack(spacing: 2) {
                                HStack(spacing: 1) { ForEach(Array([2, 4, 7, 5, 9, 7, 4, 6, 3, 5, 8, 5, 4, 7, 11, 8, 6, 5, 3, 6, 4, 5, 4, 3, 2].enumerated()), id: \.offset) { _, height in Capsule().fill(.white).frame(width: 1, height: CGFloat(height)) } }.frame(height: 16)
                                RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.25)).frame(width: 56, height: 6)
                            }.frame(width: 62, height: 30).background(.black, in: RoundedRectangle(cornerRadius: 6))
                        } else { HStack(spacing: 2) { ForEach(Array([4, 8, 11, 6, 4, 8, 5].enumerated()), id: \.offset) { _, height in Capsule().fill(.white).frame(width: 2, height: CGFloat(height)) } }.frame(width: 50, height: 20).background(.black, in: Capsule()) }
                    }
                }.frame(width: values.first == "Auto" ? 70 : 95, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.2), lineWidth: 0.5)).overlay(RoundedRectangle(cornerRadius: 10).stroke(selection.wrappedValue == value ? Color(red: 0/255, green: 145/255, blue: 255/255) : .clear, lineWidth: 2).padding(-3))
                Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1).fixedSize(horizontal: true, vertical: false).foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
            } }.buttonStyle(.plain)
        } }
    }
    private func keyLabel(_ code: Int) -> String { let letters = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"]; return code == 49 ? "Space" : code == 53 ? "esc" : (letters[code] ?? "Key \(code)") }
    private func keycap(_ text: String) -> some View { Text(text).font(.system(size: 11, weight: .semibold)).padding(.horizontal, text.count == 1 && !text.first!.isLetter ? 3 : 6).padding(.vertical, 2).background(Color.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: 4)) }
    private func shortcutRow(_ title: String, subtitle: String, key: String, modifiers: String?, fallback: Int, enabled: String? = nil) -> some View {
        HStack { VStack(alignment: .leading, spacing: 2) { Text(title); Text(subtitle).font(.system(size: 10)).foregroundStyle(scheme == .dark ? Color(red: 217/255, green: 218/255, blue: 222/255) : Color(white: 93/255)) }; Spacer(); Button { if let enabled { SettingsDefaults.store.set(false, forKey: enabled) } else { SettingsDefaults.store.removeObject(forKey: key); if let modifiers { SettingsDefaults.store.removeObject(forKey: modifiers) } }; controller.objectWillChange.send() } label: { Image(systemName: enabled == nil ? "arrow.counterclockwise" : "xmark").font(.system(size: 10)).foregroundStyle(.secondary) }.buttonStyle(.plain); ZStack { HStack(spacing: 4) { if let enabled, !SettingsDefaults.store.bool(forKey: enabled) { Text("Record shortcut").font(.system(size: 10)).foregroundStyle(scheme == .dark ? Color(red: 217/255, green: 218/255, blue: 222/255) : Color(white: 93/255)) } else { let raw = modifiers == "pushHotkeyModifiers" ? pushHotkeyModifiers : (modifiers == nil ? 0 : hotkeyModifiers); let flags = NSEvent.ModifierFlags(rawValue: UInt(raw)); if flags.contains(.control) { keycap("⌃") }; if flags.contains(.option) { keycap("⌥") }; if flags.contains(.shift) { keycap("⇧") }; if flags.contains(.command) { keycap("⌘") }; let code = key == "cancelHotkeyCode" ? cancelHotkeyCode : (key == "pushHotkeyCode" ? pushHotkeyCode : hotkeyCode); keycap(keyLabel(code)) } } }.overlay { ShortcutRecorder(codeKey: key, modifiersKey: modifiers, fallbackCode: fallback, enabledKey: enabled).opacity(0.015) }.id("\(key)-\(hotkeyCode)-\(hotkeyModifiers)-\(cancelHotkeyCode)-\(pushShortcutEnabled)-\(pushHotkeyCode)-\(pushHotkeyModifiers)").fixedSize(horizontal: true, vertical: false).frame(minHeight: 28) }.padding(.trailing, 6).frame(minHeight: 50)
    }
}

private struct ThemeArtwork: View {
    let mode: Int
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if mode == 0 {
                    HStack(spacing: 0) { desktop(dark: true); desktop(dark: false) }
                } else {
                    desktop(dark: mode == 2)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
    }
    private func desktop(dark: Bool) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: dark ? [Color(red: 0.23, green: 0.16, blue: 0.50), Color(red: 0.01, green: 0.05, blue: 0.28), Color(red: 0.01, green: 0.20, blue: 0.60)] : [Color(red: 0.82, green: 0.82, blue: 0.77), Color(red: 0.35, green: 0.70, blue: 0.90), Color(red: 0.01, green: 0.17, blue: 0.59)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 25)); path.addLine(to: CGPoint(x: 35, y: 0)); path.addLine(to: CGPoint(x: 50, y: 0)); path.addLine(to: CGPoint(x: 12, y: 28)); path.closeSubpath()
                }.fill(Color.white.opacity(dark ? 0.13 : 0.28))
                RoundedRectangle(cornerRadius: 3).fill(dark ? Color(red: 0.01, green: 0.12, blue: 0.40) : Color(red: 0.43, green: 0.72, blue: 0.94)).frame(width: 39, height: 14).overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.28), lineWidth: 0.5)).offset(x: max(0, geometry.size.width - 41), y: 6)
                RoundedRectangle(cornerRadius: 8).fill(dark ? Color(red: 0.03, green: 0.04, blue: 0.09) : Color(red: 0.91, green: 0.94, blue: 0.98)).frame(width: 52, height: 25).overlay(alignment: .topLeading) { HStack(spacing: 4) { Circle().fill(Color.green); Circle().fill(Color.yellow); Circle().fill(Color.red) }.frame(height: 6).padding(.leading, 10).padding(.top, 9) }.offset(x: 0, y: 25)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4).offset(x: max(0, geometry.size.width - 7), y: 3)
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}

private struct AdvancedSettingsRowsKey: EnvironmentKey { static let defaultValue = false }
private extension EnvironmentValues {
    var advancedSettingsRows: Bool {
        get { self[AdvancedSettingsRowsKey.self] }
        set { self[AdvancedSettingsRowsKey.self] = newValue }
    }
}

private struct ConfigurationApplicationRow<Content: View>: View {
    @Environment(\.advancedSettingsRows) private var advanced
    let title: String
    var help: String? = nil
    @ViewBuilder var content: Content
    var body: some View { HStack(spacing: 8) { Text(title); if let help { Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help(help) }; Spacer(); content }.frame(minHeight: title == "Keep recordings for" ? 58 : (advanced ? 46 : 43)) }
}

private struct PageRule: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(scheme == .dark ? Color(red: 80/255, green: 81/255, blue: 86/255) : Color(white: 226/255)).frame(height: 0.5) }
}

private struct RetentionPopup: View {
    @Binding var selection: Int
    private let options = [(0, "Forever"), (1, "1 day"), (7, "1 week"), (14, "2 weeks"), (30, "1 month"), (180, "6 months"), (365, "1 year")]
    private let surface = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 75/255, green: 77/255, blue: 82/255, alpha: 1)
            : NSColor(srgbRed: 253/255, green: 253/255, blue: 253/255, alpha: 1)
    }))
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { option in Button(option.1) { selection = option.0 } }
        } label: {
            HStack { Text(options.first(where: { $0.0 == selection })?.1 ?? "Forever"); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }
                .padding(.horizontal, 9).frame(width: 125, height: 28)
                .background(surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.10), radius: 1, y: 1)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 125, height: 28)
    }
}

/// Native popup chrome keeps the indicator and enclosing surface together.
private struct SettingsPopup: NSViewRepresentable {
    @Binding var selection: Int
    let options: [(Int, String)]
    let width: CGFloat
    init(selection: Binding<Int>, options: [(Int, String)], width: CGFloat) {
        self._selection = selection; self.options = options; self.width = width
    }
    init(selection: Binding<Int>, options: [String], width: CGFloat) {
        self.init(selection: selection, options: Array(options.enumerated()).map { ($0.offset, $0.element) }, width: width)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.target = context.coordinator; button.action = #selector(Coordinator.changed(_:))
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if button.itemTitles != options.map(\.1) { button.removeAllItems(); button.addItems(withTitles: options.map(\.1)) }
        if let index = options.firstIndex(where: { $0.0 == selection }) { button.selectItem(at: index) }
    }
    final class Coordinator: NSObject {
        var parent: SettingsPopup
        init(_ parent: SettingsPopup) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard parent.options.indices.contains(sender.indexOfSelectedItem) else { return }
            parent.selection = parent.options[sender.indexOfSelectedItem].0
            if let index = parent.options.firstIndex(where: { $0.0 == parent.selection }) { sender.selectItem(at: index) }
        }
    }
}

// A child panel covers the entire parent frame, including the title bar.
private struct ConfirmationFrameOverlay: NSViewRepresentable {
    let model: Model?
    let name: String
    let cancel: () -> Void
    let delete: (Model) -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.update(model: model, name: name, cancel: cancel, delete: delete)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.removeOverlay() }

    final class Anchor: NSView {
        private var panel: ScrimPanel?
        private var card: ConfirmationCard?
        private var observers: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); install() }
        func update(model: Model?, name: String, cancel: @escaping () -> Void, delete: @escaping (Model) -> Void) {
            guard let model else { card = nil; removeOverlay(); return }
            card = ConfirmationCard(model: model, name: name, cancel: cancel, delete: { delete(model) })
            install()
        }
        private func install() {
            guard let card, let window else { return }
            if let panel { (panel.contentView as? NSHostingView<ConfirmationCard>)?.rootView = card; return }
            let panel = ScrimPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: card)
            panel.setFrame(window.frame, display: true)
            window.addChildWindow(panel, ordered: .above)
            self.panel = panel
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak panel, weak window] _ in
                    if let window { panel?.setFrame(window.frame, display: true) }
                })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                if event.keyCode == 53, event.window === window { self?.card?.cancel(); return nil }
                return event
            }
        }
        func removeOverlay() {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
            if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil); self.panel = nil }
        }
        deinit { removeOverlay() }
    }
    final class ScrimPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}

private struct ConfirmationCard: View {
    let model: Model
    let name: String
    let cancel: () -> Void
    let delete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            Color.black.opacity(0.50)
            VStack(alignment: .leading, spacing: 11) {
                Text("Delete \(name)").font(.system(size: 13, weight: .bold))
                Text(model.engine == "apple" ? "LightTTS will forget this selection; macOS manages the speech assets." : model.engine == "cloud" ? "The model and its API key will be removed." : "Are you sure you want to delete this model?").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Cancel", action: cancel).keyboardShortcut(.cancelAction).buttonStyle(AlertButton(destructive: false))
                    Button("Delete", role: .destructive, action: delete).buttonStyle(AlertButton(destructive: true))
                }
            }.padding(20).frame(width: 260).background(colorScheme == .dark ? Color(red: 18/255, green: 19/255, blue: 23/255) : Color(red: 179/255, green: 180/255, blue: 184/255), in: RoundedRectangle(cornerRadius: 34)).shadow(radius: 18).offset(y: -14)
        }.ignoresSafeArea()
    }
}

private struct AlertButton: ButtonStyle {
    let destructive: Bool
    @Environment(\.colorScheme) private var colorScheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(destructive ? Color.red : Color.primary).frame(maxWidth: .infinity).frame(height: 28).background(destructive ? (colorScheme == .dark ? Color(red: 37/255, green: 21/255, blue: 22/255) : Color.red.opacity(configuration.isPressed ? 0.3 : 0.14)) : Color.primary.opacity(configuration.isPressed ? 0.2 : 0.12), in: Capsule())
    }
}
