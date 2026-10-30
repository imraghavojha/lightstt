import SwiftUI
import AppKit
import LightTTSCore
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("keepModelLoaded") private var keepModelLoaded = true
    @AppStorage("customModelURL") private var customModelURL = ""
    @AppStorage("customModelSHA256") private var customModelSHA256 = ""
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading) {
                ForEach(["Sound", "Models", "Library", "Configuration"], id: \.self) { tab in Button(tab) { controller.settingsSelection = tab }.buttonStyle(.plain).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(controller.settingsSelection == tab ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6)) }
                Spacer(); Button(attached ? "Detach into window" : "Back to menu") { detach() }; Button("Quit LightTTS") { NSApp.terminate(nil) }
            }.padding().frame(width: 150).background(.quaternary.opacity(0.4))
            VStack(alignment: .leading) {
                if controller.settingsSelection != "Models" { Text(controller.settingsSelection).font(.title2.bold()) }
                switch controller.settingsSelection {
                case "Sound": Text("Microphone: system default"); Text("Audio is processed locally at 16 kHz mono.").foregroundStyle(.secondary)
                case "Models":
                    ModelsPageView(controller: controller)
                case "Library": ScrollView { LazyVStack(alignment: .leading) { ForEach(controller.history) { item in VStack(alignment: .leading) { Text(item.text); Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading); Divider() } } }
                default:
                    Toggle("Push to talk", isOn: $pushToTalk)
                    Toggle("Use Right Option only", isOn: $rightOption)
                    Toggle("Keep model loaded between recordings", isOn: $keepModelLoaded)
                    Text("Loaded models are released after five minutes of inactivity.").font(.caption).foregroundStyle(.secondary)
                    HStack { Text("Option + key code:"); TextField("49 (Space)", value: $hotkeyCode, format: .number).frame(width: 80).disabled(rightOption) }
                    Button("Request permissions / Retry shortcut") { controller.requestPermissions() }
                    Text("Enable Accessibility and Input Monitoring in System Settings, then retry the shortcut. Accessibility allows text insertion.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(controller.settingsSelection == "Models" ? 0 : 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 650, height: 440).onChange(of: selectedModel) { _ in controller.warmSelected() }
    }
}
