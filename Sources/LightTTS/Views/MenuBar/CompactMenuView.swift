import AppKit
import AVFoundation
@preconcurrency import LightTTSCore
import SwiftUI

@MainActor final class CompactMenuData: ObservableObject {
    @Published var devices: [InputDevice] = []
    @Published var defaultName = "Microphone"
    @Published var installedModels: [Model] = []
    private var generation = 0
    func load(models: [Model]) {
        generation += 1
        let current = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = models.filter { ModelStore.exists($0) }
            let available = InputDevice.available
            let systemName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone"
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == current else { return }
                self.installedModels = installed; self.devices = available; self.defaultName = systemName
            }
        }
    }
}

struct CompactMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: AppController
    let openSettings: () -> Void
    let recordingAction: () -> Void
    let cancelRecording: () -> Void
    @AppStorage("selectedModel") private var selectedModel = ModelDefaults.selectedModel
    @AppStorage("inputDeviceUID") private var selectedInput = ""
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("pushShortcutEnabled") private var pushShortcutEnabled = false
    @ObservedObject var data: CompactMenuData
    private var modelName: String { data.installedModels.first { $0.id == selectedModel }?.name ?? "Choose a model…" }
    private var inputName: String { data.devices.first { $0.id == selectedInput }?.name ?? "\(data.defaultName) (Default)" }

    var body: some View {
        VStack(spacing: 0) {
            switch controller.state {
            case "idle", "recording":
                Button(action: recordingAction) {
                    HStack {
                        Text(controller.state == "idle" ? "Start Recording" : "Stop Recording")
                        Spacer()
                        Text(ShortcutButton.displayName(.toggle)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle()).padding(.horizontal, 14).frame(height: 32)
                }.buttonStyle(.plain)
                .help("Toggle recording (\(ShortcutButton.displayName(.toggle)))")
                if controller.state == "recording" {
                    Button("Cancel Recording", action: cancelRecording)
                        .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 32)
                }
                Divider().padding(.horizontal, 14).padding(.vertical, 4)
            case "starting", "loading", "processing":
                HStack {
                    ProgressView().controlSize(.small)
                    Text(controller.state == "starting" ? "Starting recording…" : controller.state == "loading" ? "Loading model…" : "Processing recording…")
                    Spacer()
                    Button("Cancel", action: recordingAction).buttonStyle(.plain)
                }.padding(.horizontal, 14).frame(height: 32)
                Divider().padding(.horizontal, 14).padding(.vertical, 4)
            default: EmptyView()
            }
            if controller.state == "error" {
                Button("Dismiss error") { controller.cancel() }
                    .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 32)
                Divider().padding(.horizontal, 14).padding(.vertical, 4)
            }
            HStack(spacing: 8) {
                Text("Model").frame(width: 100, alignment: .leading)
                Menu {
                    if data.installedModels.isEmpty { Button("Open Models settings…") { controller.settingsSelection = "Models"; openSettings() } }
                    ForEach(data.installedModels) { model in
                        Button { selectedModel = model.id; controller.reloadSelectedModel() } label: {
                            if model.id == selectedModel { Label(model.name, systemImage: "checkmark") }
                            else { Text(model.name) }
                        }
                    }
                } label: { Color.clear.frame(width: 136, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 136)
                .overlay(alignment: .leading) { Text(modelName).lineLimit(1).truncationMode(.middle).frame(width: 136, alignment: .leading).allowsHitTesting(false) }
                .accessibilityLabel("Model: \(modelName)").help(modelName)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).frame(height: 34)

            HStack(spacing: 8) {
                Text("Microphone").frame(width: 100, alignment: .leading)
                Menu {
                    Button { selectedInput = "" } label: {
                        if selectedInput.isEmpty { Label("\(data.defaultName) (Default)", systemImage: "checkmark") }
                        else { Text("\(data.defaultName) (Default)") }
                    }
                    ForEach(data.devices) { device in
                        Button { selectedInput = device.id } label: {
                            if selectedInput == device.id { Label(device.name, systemImage: "checkmark") }
                            else { Text(device.name) }
                        }
                    }
                } label: { Color.clear.frame(width: 136, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 136)
                .overlay(alignment: .leading) { Text(selectedInput.isEmpty ? data.defaultName : inputName).lineLimit(1).truncationMode(.middle).frame(width: 136, alignment: .leading).allowsHitTesting(false) }
                .accessibilityLabel("Microphone: \(inputName)").help(inputName)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).frame(height: 34)

            Divider().padding(.horizontal, 14).padding(.vertical, 4)
            HStack { Text("Auto-paste"); Spacer(); Toggle("Auto-paste", isOn: $autoPaste).labelsHidden().toggleStyle(.switch).controlSize(.mini) }.padding(.horizontal, 14).frame(height: 34)
            HStack { Text("Push to talk"); Spacer(); Toggle("Push to talk", isOn: $pushShortcutEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini).onChange(of: pushShortcutEnabled) { _ in NotificationCenter.default.post(name: .shortcutsChanged, object: nil) } }.padding(.horizontal, 14).frame(height: 34)
            Divider().padding(.horizontal, 14).padding(.vertical, 4)
            Button(action: openSettings) {
                HStack { Text("Settings…"); Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                    .contentShape(Rectangle()).padding(.horizontal, 14).frame(height: 32)
            }.buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
        .frame(width: 292)
        .background(colorScheme == .dark ? Color(red: 0.125, green: 0.125, blue: 0.125) : Color(red: 0.96, green: 0.96, blue: 0.96))

        .onChange(of: controller.models) { models in data.load(models: models) }
    }
}
