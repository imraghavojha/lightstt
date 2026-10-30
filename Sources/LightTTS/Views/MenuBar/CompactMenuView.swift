import AppKit
import AVFoundation
@preconcurrency import LightTTSCore
import SwiftUI

@MainActor final class CompactMenuData: ObservableObject {
    @Published var devices: [InputDevice] = []
    @Published var defaultName = "Microphone"
    @Published var installedModels: [Model] = []
    func load(models: [Model]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = models.filter { ModelStore.exists($0) }
            let available = InputDevice.available
            let systemName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone"
            DispatchQueue.main.async { [weak self] in
                self?.installedModels = installed; self?.devices = available; self?.defaultName = systemName
            }
        }
    }
}

struct CompactMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var controller: AppController
    let openSettings: () -> Void
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("inputDeviceUID") private var selectedInput = ""
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("pushToTalk") private var pushToTalk = false
    @StateObject private var data = CompactMenuData()
    private var modelName: String { data.installedModels.first { $0.id == selectedModel }?.name ?? "Choose a model…" }
    private var inputName: String { data.devices.first { $0.id == selectedInput }?.name ?? "\(data.defaultName) (Default)" }

    var body: some View {
        VStack(spacing: 0) {
            if controller.state == "error" {
                Button("Retry recording") { controller.cancel(); controller.start() }
                    .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 32)
                Divider().padding(.horizontal, 14).padding(.vertical, 4)
            }
            Menu {
                if data.installedModels.isEmpty { Button("Open Models settings…") { controller.settingsSelection = "Models"; openSettings() } }
                ForEach(data.installedModels) { model in
                    Button { selectedModel = model.id; controller.warmSelected() } label: {
                        if model.id == selectedModel { Label(model.name, systemImage: "checkmark") }
                        else { Text(model.name) }
                    }
                }
            } label: { menuRow("Model", value: modelName) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 292, height: 34)

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
            } label: { menuRow("Microphone", value: inputName) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 292, height: 34)

            Divider().padding(.horizontal, 14).padding(.vertical, 4)
            HStack { Text("Auto-paste"); Spacer(); Toggle("Auto-paste", isOn: $autoPaste).labelsHidden().toggleStyle(.switch).controlSize(.mini) }.padding(.horizontal, 14).frame(height: 34)
            HStack { Text("Push to talk"); Spacer(); Toggle("Push to talk", isOn: $pushToTalk).labelsHidden().toggleStyle(.switch).controlSize(.mini) }.padding(.horizontal, 14).frame(height: 34)
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
        .onAppear { data.load(models: controller.models) }
    }
    private func menuRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer(minLength: 4)
            Text(value).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }.contentShape(Rectangle()).padding(.horizontal, 14).frame(width: 292, height: 34)
    }
}
