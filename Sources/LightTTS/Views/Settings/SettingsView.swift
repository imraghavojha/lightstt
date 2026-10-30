import SwiftUI
import AppKit
import LightTTSCore
import ApplicationServices

private final class SettingsDialogState: ObservableObject { @Published var deleting: Model? }

struct SettingsView: View {
    @ObservedObject var controller: AppController
    var detach: () -> Void
    var attached: Bool
    @StateObject private var dialog = SettingsDialogState()
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("pushToTalk") private var pushToTalk = false
    @AppStorage("rightOption") private var rightOption = false
    @AppStorage("keepModelLoaded") private var keepModelLoaded = true
    @AppStorage("customModelURL") private var customModelURL = ""
    @AppStorage("customModelSHA256") private var customModelSHA256 = ""
    @AppStorage("hotkeyCode") private var hotkeyCode = 49
    private func alertName(_ model: Model) -> String {
        switch model.id {
        case "whisper-large-v3": return "Whisper Large"
        case "whisper-large-v3-turbo": return "Whisper Large v3 Turbo"
        case "whisper-medium": return "Whisper Medium"
        case "whisper-small", "whisper-small.en": return "Whisper Small"
        case "whisper-tiny", "whisper-tiny.en": return "Whisper Tiny"
        default: return model.name
        }
    }
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
                    ModelsPageView(controller: controller, deleting: $dialog.deleting)
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
        }.frame(width: 650, height: 440)
        .alert("Delete \(dialog.deleting.map(alertName) ?? "model")", isPresented: Binding(
            get: { dialog.deleting != nil },
            set: { if !$0 { dialog.deleting = nil } }
        ), presenting: dialog.deleting) { model in
            Button("Cancel", role: .cancel) { dialog.deleting = nil }
            Button("Delete", role: .destructive) {
                do { try controller.deleteModel(model) } catch { controller.message = error.localizedDescription }
                dialog.deleting = nil
            }
        } message: { model in
            Text(model.engine == "apple" ? "LightTTS will forget this selection; macOS manages the speech assets." : model.engine == "cloud" ? "The model and its API key will be removed." : "Are you sure you want to delete this model?")
        }
        .onChange(of: selectedModel) { _ in controller.warmSelected() }
    }
}
