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
                Text(controller.settingsSelection).font(.title2.bold())
                switch controller.settingsSelection {
                case "Sound": Text("Microphone: system default"); Text("Audio is processed locally at 16 kHz mono.").foregroundStyle(.secondary)
                case "Models":
                    Picker("Selected model", selection: $selectedModel) { ForEach(controller.models) { Text($0.name).tag($0.id) } }
                    ScrollView { LazyVStack(alignment: .leading) { ForEach(controller.models) { model in HStack { Text(model.name); Spacer(); if ModelStore.exists(model) { Button("Delete") { controller.deleteModel(model) } } else { Button(controller.busyModel == model.id ? "Downloading…" : "Download") { controller.download(model) }.disabled(controller.busyModel != nil) } } } } }
                    HStack { Button("Import file…") { controller.importLocalModel() }; TextField("Model URL", text: $customModelURL); Button("Import URL") { controller.importRemoteModel(customModelURL, sha256: customModelSHA256) } }
                    TextField("SHA-256 for URL import", text: $customModelSHA256)
                    if controller.busyModel != nil { HStack { ProgressView(value: controller.downloadProgress); Button("Cancel") { controller.cancelDownload() } } }
                    if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red) }
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
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(width: 650, height: 440).onChange(of: selectedModel) { _ in controller.warmSelected() }
    }
}
