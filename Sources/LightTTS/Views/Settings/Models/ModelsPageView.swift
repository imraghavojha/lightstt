import SwiftUI
import AppKit
import LightTTSCore

private final class ModelsPageState: ObservableObject {
    @Published var query = ""
    @Published var searching = false
    @Published var installedOnly = false
    @Published var detail: Model?
    @Published var custom = false
    @Published var deleting: Model?
}
private final class CustomModelState: ObservableObject {
    @Published var address = ""
    @Published var sha256 = ""
    @Published var kind = "whisper"
    var engine: String { if kind.hasPrefix("sherpa:") { return "sherpa" }; if kind.hasPrefix("parakeet:") { return "parakeet" }; return kind }
    var version: String { kind.split(separator: ":").dropFirst().first.map(String.init) ?? "" }
}

struct ModelsPageView: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("favoriteModels") private var favorites = "whisper-large-v3,whisper-large-v3-turbo,whisper-medium,whisper-small,whisper-small.en"
    @StateObject private var ui = ModelsPageState()

    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }
    private var visible: [Model] {
        let preferred = ["whisper-large-v3", "whisper-large-v3-turbo", "whisper-medium", "whisper-small", "whisper-small.en"]
        return controller.models.filter { (ui.query.isEmpty || $0.name.localizedCaseInsensitiveContains(ui.query)) && (!ui.installedOnly || ModelStore.exists($0)) }.sorted { a, b in
            let x = preferred.firstIndex(of: a.id) ?? preferred.count
            let y = preferred.firstIndex(of: b.id) ?? preferred.count
            return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x < y
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Models library").font(.system(size: 14, weight: .bold))
                Spacer()
                if ui.detail == nil {
                    if ui.searching { TextField("Search models", text: $ui.query).textFieldStyle(.roundedBorder).frame(width: 155) }
                    Button { ui.searching.toggle(); if !ui.searching { ui.query = "" } } label: { Image(systemName: "magnifyingglass") }.buttonStyle(CircleButton()).help("Search")
                    Menu { Toggle("Downloaded only", isOn: $ui.installedOnly) } label: { Image(systemName: "line.3.horizontal.decrease") }.menuStyle(.borderlessButton).frame(width: 28).help("Filters")
                    Button { ui.custom = true } label: { Image(systemName: "plus") }.buttonStyle(CircleButton()).help("Add custom model")
                }
            }.padding(.horizontal, 20).padding(.vertical, 16)
            library
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red).padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 12) }
        }
        .background(colorScheme == .dark ? Color(red: 44/255, green: 47/255, blue: 52/255) : Color(red: 242/255, green: 242/255, blue: 242/255))
        .overlay(alignment: .trailing) {
            if let model = ui.detail {
                detailView(model).frame(width: 400).frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
            }
        }
        .sheet(isPresented: $ui.custom) { CustomModelSheet(controller: controller) }
        .alert("Delete model?", isPresented: Binding(get: { ui.deleting != nil }, set: { if !$0 { ui.deleting = nil } })) {
            Button("Cancel", role: .cancel) { ui.deleting = nil }
            Button("Delete", role: .destructive) { if let model = ui.deleting { do { try controller.deleteModel(model) } catch { controller.message = error.localizedDescription } }; ui.deleting = nil }
        } message: { Text(ui.deleting?.engine == "apple" ? "LightTTS will forget this selection; macOS manages the speech assets." : "The downloaded files will be removed from this Mac.") }
    }
    private var library: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Model name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Type").frame(width: 45, alignment: .leading)
                Text("Speed / Accuracy").frame(width: 100, alignment: .leading)
                Text("Cloud/Offline").frame(width: 90, alignment: .trailing)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 12)
            ScrollView { LazyVStack(spacing: 0) { ForEach(visible) { model in
                HStack(spacing: 8) {
                    Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star").foregroundStyle(favoriteIDs.contains(model.id) ? Color.primary : Color.secondary) }.buttonStyle(.plain)
                    provider(model)
                    Button { ui.detail = model } label: { HStack(spacing: 4) { Text(model.name).lineLimit(1); if model.id.contains(".en") { Text("EN").font(.system(size: 8, weight: .bold)).padding(3).background(.quaternary, in: Capsule()) } } }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "waveform").foregroundStyle(.secondary).frame(width: 24, height: 21).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)).frame(width: 45, alignment: .leading)
                    ratings(model).frame(width: 100, alignment: .leading)
                    HStack(spacing: 6) { if controller.busyModel == model.id { Text("\(Int(controller.downloadProgress * 100))%"); Button { controller.cancelDownload() } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain) } else { Text(size(model)).foregroundStyle(.secondary); action(model) } }.frame(width: 90, alignment: .trailing)
                }.font(.system(size: 13)).frame(height: 36).padding(.horizontal, 20)
            } } }
        }
    }
    private func detailView(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { ui.detail = nil } label: { Image(systemName: "chevron.left") }.buttonStyle(CircleButton())
                Spacer(); provider(model)
                VStack(alignment: .leading, spacing: 1) { Text(model.name).font(.system(size: 13, weight: .bold)); Text(providerName(model)).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(); Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star") }.buttonStyle(.plain)
            }
            Text(engineDescription(model)).foregroundStyle(.secondary)
            VStack(spacing: 12) {
                HStack { Text("Type").foregroundStyle(.secondary); Spacer(); Text("Voice model") }
                HStack { Text("Specs"); Spacer(); Image(systemName: "waveform").foregroundStyle(.secondary) }
                HStack { Text("Speed"); Spacer(); rating(model.speed) }
                HStack { Text("Accuracy"); Spacer(); rating(model.accuracy) }
                HStack { Text("Size").foregroundStyle(.secondary); Spacer(); Text(size(model)) }
                HStack { Text("Language").foregroundStyle(.secondary); Spacer(); Text(model.languages?.joined(separator: ", ") ?? "See model source").lineLimit(1) }
            }.padding(16).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            HStack { if ModelStore.exists(model) { Button(selectedModel == model.id ? "Selected" : "Use in all modes") { selectedModel = model.id; controller.warmSelected() }.frame(maxWidth: .infinity).disabled(selectedModel == model.id); Button(role: .destructive) { ui.deleting = model } label: { Image(systemName: "trash") } } else if controller.busyModel == model.id { Text("Downloading \(Int(controller.downloadProgress * 100))%"); Button("Cancel") { controller.cancelDownload() } } else { Button("Download") { controller.download(model) }.disabled(controller.busyModel != nil) } }
        }.font(.system(size: 12)).padding(16)
    }
    private func providerName(_ model: Model) -> String {
        switch model.engine { case "parakeet", "canary": return "NVIDIA"; case "sherpa": return "ONNX"; case "apple": return "Apple"; default: return "OpenAI" }
    }
    private func engineDescription(_ model: Model) -> String {
        switch model.engine { case "parakeet", "canary": return "On-device speech recognition using Core ML."; case "sherpa": return "Offline speech recognition using sherpa-onnx."; case "apple": return "On-device speech recognition using Apple Speech."; default: return "Offline speech recognition using whisper.cpp." }
    }
    private func provider(_ model: Model) -> some View { Text(String(providerName(model).prefix(1))).font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 19, height: 19).background((model.engine == "parakeet" || model.engine == "canary") ? Color.green : Color.gray, in: RoundedRectangle(cornerRadius: 5)) }
    private func ratings(_ model: Model) -> some View { VStack(alignment: .leading, spacing: 2) { rating(model.speed); rating(model.accuracy) } }
    private func rating(_ value: Int?) -> some View { HStack(spacing: 2) { ForEach(0..<5) { i in Capsule().fill(i < (value ?? 0) ? Color.primary.opacity(0.7) : Color.primary.opacity(0.15)).frame(width: 9, height: 3) } } }
    private func size(_ model: Model) -> String { model.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—" }
    private func action(_ model: Model) -> some View { Button { if ModelStore.exists(model) { ui.deleting = model } else { controller.download(model) } } label: { Image(systemName: ModelStore.exists(model) ? "trash" : "arrow.down.circle") }.buttonStyle(.plain).disabled(controller.busyModel != nil).help(ModelStore.exists(model) ? "Delete" : "Download") }
    private func toggleFavorite(_ model: Model) { var ids = favoriteIDs; if !ids.insert(model.id).inserted { ids.remove(model.id) }; favorites = ids.sorted().joined(separator: ",") }
}

private struct CircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 11, weight: .medium)).frame(width: 26, height: 26).background(Color.primary.opacity(configuration.isPressed ? 0.17 : 0.08), in: Circle()) }
}

private struct CustomModelSheet: View {
    @ObservedObject var controller: AppController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = CustomModelState()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add custom model").font(.headline)
            Text("Choose an engine and compatible local model. Whisper accepts a direct URL or repository; other engines accept a Hugging Face repository or an HTTP(S) model manifest.").foregroundStyle(.secondary)
            Picker("Engine / format", selection: $ui.kind) {
                Text("whisper.cpp GGML").tag("whisper")
                Text("sherpa-onnx Moonshine").tag("sherpa:moonshine")
                Text("sherpa-onnx SenseVoice").tag("sherpa:sense_voice")
                Text("sherpa-onnx Paraformer").tag("sherpa:paraformer")
                Text("sherpa-onnx Zipformer").tag("sherpa:zipformer")
                Text("sherpa-onnx Whisper").tag("sherpa:whisper_onnx")
                Text("sherpa-onnx Parakeet").tag("sherpa:nemo_parakeet")
                Text("sherpa-onnx Canary").tag("sherpa:nemo_canary")
                Text("Core ML Parakeet v2").tag("parakeet:v2")
                Text("Core ML Parakeet v3").tag("parakeet:v3")
                Text("Core ML Parakeet Ultra").tag("parakeet:ultra")
                Text("Core ML Parakeet Redux").tag("parakeet:redux")
                Text("Core ML Parakeet 110M").tag("parakeet:tdt-ctc-110m")
                Text("Core ML Parakeet Japanese").tag("parakeet:ja")
                Text("Core ML Canary").tag("canary")
            }
            if ui.engine != "apple" { TextField(ui.engine == "whisper" ? "Model URL or owner/repository" : "Hugging Face repository or manifest URL", text: $ui.address).textFieldStyle(.roundedBorder) }
            if ui.engine == "whisper" { TextField("SHA-256 for URL import", text: $ui.sha256).textFieldStyle(.roundedBorder) }
            HStack { Button("Choose local file…") { controller.importLocalModel(engine: ui.engine, version: ui.version); dismiss() }; Spacer(); Button("Cancel") { dismiss() }; if ui.engine != "apple" { Button("Add URL") { if ui.engine == "whisper" { controller.importRemoteModel(ui.address, sha256: ui.sha256) } else if ui.address.hasPrefix("http://") || (ui.address.hasPrefix("https://") && !ui.address.hasPrefix("https://huggingface.co/")) { controller.importModelManifest(ui.address, engine: ui.engine, version: ui.version) } else { controller.importModelRepository(ui.address, engine: ui.engine, version: ui.version) }; dismiss() }.disabled(ui.address.isEmpty || (ui.engine == "whisper" && ui.sha256.count != 64)) } }.controlSize(.small)
        }.padding(24).frame(width: 470)
    }
}
