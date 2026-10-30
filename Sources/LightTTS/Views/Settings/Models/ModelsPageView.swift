import SwiftUI
import AppKit
import LightTTSCore

private final class ModelsPageState: ObservableObject {
    @Published var query = ""
    @Published var searching = false
    @Published var installedOnly = false
    @Published var detail: Model?
    @Published var custom = false
    @Published var cloud = false
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
        return controller.models.filter { (ui.query.isEmpty || $0.name.localizedCaseInsensitiveContains(ui.query) || displayName($0).localizedCaseInsensitiveContains(ui.query)) && (!ui.installedOnly || ModelStore.exists($0)) }.sorted { a, b in
            let x = preferred.firstIndex(of: a.id) ?? preferred.count
            let y = preferred.firstIndex(of: b.id) ?? preferred.count
            return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x < y
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Models library").font(.system(size: 14, weight: .bold)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 4)
                if ui.searching {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search models", text: $ui.query).textFieldStyle(.plain)
                        Button { ui.query = ""; ui.searching = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search")
                    }.font(.system(size: 12)).padding(.horizontal, 10).frame(width: 220, height: 28).background(Color.primary.opacity(0.08), in: Capsule())
                } else { Button { ui.searching = true } label: { Image(systemName: "magnifyingglass") }.buttonStyle(CircleButton()).help("Search") }
                Menu { Toggle("Downloaded only", isOn: $ui.installedOnly) } label: { toolbarIcon("line.3.horizontal.decrease") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)).help("Filters")
                Menu { Button("Add cloud model…") { ui.cloud = true }; Button("Add local model…") { ui.custom = true } } label: { toolbarIcon("key.fill", plus: true) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)).help("Bring your own key")
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 12)
            library
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 8) }
        }
        .background(colorScheme == .dark ? Color(red: 44/255, green: 47/255, blue: 52/255) : Color(red: 242/255, green: 242/255, blue: 242/255))
        .overlay { if ui.detail != nil { Color.black.opacity(colorScheme == .dark ? 0.24 : 0.12).allowsHitTesting(false) } }
        .overlay(alignment: .trailing) {
            if let model = ui.detail {
                detailView(model).frame(width: 400).frame(maxHeight: .infinity)
                    .background(colorScheme == .dark ? Color(red: 42/255, green: 48/255, blue: 56/255) : Color(red: 231/255, green: 235/255, blue: 240/255))
                    .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1) }
            }
        }
        .task { await ModelStore.refreshAppleStatus(); controller.objectWillChange.send() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await ModelStore.refreshAppleStatus(); controller.objectWillChange.send() } }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in Task { await ModelStore.refreshAppleStatus(); controller.objectWillChange.send() } }
        .sheet(isPresented: $ui.custom) { CustomModelSheet(controller: controller) }
        .sheet(isPresented: $ui.cloud) { CloudModelSheet(controller: controller) }
        .overlay {
            if let model = ui.deleting {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    VStack(spacing: 12) {
                        Text("Delete \(displayName(model))").font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
                        Text(model.engine == "apple" ? "LightTTS will forget this selection; macOS manages the speech assets." : model.engine == "cloud" ? "The model and its API key will be removed." : "Are you sure you want to delete this model?").font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Cancel") { ui.deleting = nil }.buttonStyle(FooterButton()).keyboardShortcut(.cancelAction)
                            Button("Delete", role: .destructive) { do { try controller.deleteModel(model) } catch { controller.message = error.localizedDescription }; ui.deleting = nil }.buttonStyle(DestructiveFooterButton())
                        }
                    }.padding(18).frame(width: 260).background(colorScheme == .dark ? Color(red: 54/255, green: 58/255, blue: 65/255) : Color(red: 231/255, green: 235/255, blue: 240/255), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15), lineWidth: 0.5)).shadow(radius: 18)
                }
            }
        }
    }
    private func toolbarIcon(_ name: String, plus: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: name).font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28)
            if plus { Image(systemName: "plus.circle.fill").font(.system(size: 8)).offset(x: 1, y: -1) }
        }.background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
    private var library: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let compact = width < 540
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    HStack(spacing: 3) { Text("Model name"); Image(systemName: "chevron.up").font(.system(size: 8)) }.frame(maxWidth: .infinity, alignment: .leading)
                    Text("Type").frame(width: compact ? 30 : 42, alignment: .leading)
                    Text("Speed / Accuracy").lineLimit(1).minimumScaleFactor(0.75).frame(width: compact ? 85 : 110, alignment: .leading)
                    Text("Cloud/Offline").frame(width: 90, alignment: .trailing)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 56).padding(.trailing, compact ? 18 : 28).padding(.top, 13).padding(.bottom, 10)
                ScrollView { LazyVStack(spacing: 0) { ForEach(visible) { model in
                    HStack(spacing: 8) {
                        Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star").foregroundStyle(favoriteIDs.contains(model.id) ? Color.primary : Color.secondary).frame(width: 24) }.buttonStyle(.plain)
                        provider(model)
                        Button { ui.detail = model } label: { HStack(spacing: 4) { Text(displayName(model)).lineLimit(1); if model.id.contains(".en") { Text("EN").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary).frame(width: 19, height: 14).background(Color.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4)) } } }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "waveform").foregroundStyle(.secondary).frame(width: 24, height: 21).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5)).frame(width: compact ? 30 : 42, alignment: .leading)
                        ratings(model).frame(width: compact ? 85 : 110, alignment: .leading)
                        HStack(spacing: 6) {
                            if controller.busyModel == model.id { Text("\(Int(controller.downloadProgress * 100))%").font(.system(size: 12, weight: .medium)); progressButton }
                            else if model.engine == "cloud" { Image(systemName: "cloud").foregroundStyle(.secondary); action(model) }
                            else { Text(size(model)).font(.system(size: 12, weight: .medium)); action(model) }
                        }.frame(width: 90, alignment: .trailing)
                    }.font(.system(size: 13)).frame(height: 36).padding(.leading, 24).padding(.trailing, compact ? 18 : 28)
                        .background(ui.detail?.id == model.id ? Color.primary.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 2)
                } }.frame(width: width) }
            }
        }
    }
    private var progressButton: some View {
        Button { controller.cancelDownload() } label: {
            ZStack { Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1.5); Circle().trim(from: 0, to: min(max(controller.downloadProgress, 0), 1)).stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(-90)); Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }.frame(width: 22, height: 22)
        }.buttonStyle(.plain).help("Cancel download")
    }
    private func detailView(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { ui.detail = nil } label: { Image(systemName: "chevron.left").font(.system(size: 12)) }.buttonStyle(.plain).frame(width: 20, height: 28)
                Spacer(); provider(model)
                VStack(alignment: .leading, spacing: 1) { Text(displayName(model)).font(.system(size: 13, weight: .bold)); Text(model.id == "whisper-large-v3-turbo" ? "Superwhisper Ultra V3 Turbo" : providerName(model)).font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer(); Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star") }.buttonStyle(.plain)
            }
            Text(engineDescription(model)).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack { Text("Type"); Spacer(); Text("Voice model").foregroundStyle(.primary) }.frame(height: 31)
                HStack { Text("Specs"); Spacer(); specs }.frame(height: 31)
                HStack { Text("Speed"); Spacer(); rating(model.speed, detail: true) }.frame(height: 31)
                HStack { Text("Accuracy"); Spacer(); rating(model.accuracy, detail: true) }.frame(height: 31)
                HStack { Text("Size"); Spacer(); Text(model.engine == "cloud" ? "Cloud" : size(model)).foregroundStyle(.primary) }.frame(height: 31)
            }.foregroundStyle(.secondary).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 8).background(colorScheme == .dark ? Color(red: 51/255, green: 56/255, blue: 64/255) : Color(red: 218/255, green: 224/255, blue: 231/255), in: RoundedRectangle(cornerRadius: 16))
            if model.engine == "canary" || model.version == "nemo_canary" { CanaryLanguagePicker(model: model, controller: controller) }
            else if let languages = model.languages { Text(languages.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            HStack(spacing: 8) {
                if ModelStore.exists(model) {
                    Button(selectedModel == model.id ? "Selected" : "Use in all modes") { selectedModel = model.id; controller.warmSelected() }.buttonStyle(FooterButton()).disabled(selectedModel == model.id)
                    Button { ui.deleting = model } label: { Image(systemName: "trash.fill").frame(width: 28, height: 28).background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                } else if controller.busyModel == model.id { Text("Downloading \(Int(controller.downloadProgress * 100))%"); Spacer(); progressButton }
                else { Button("Download") { controller.download(model) }.buttonStyle(FooterButton()).disabled(controller.busyModel != nil) }
            }
        }.font(.system(size: 12)).padding(16)
    }
    private var specs: some View {
        HStack(spacing: 5) { ForEach(["bolt.fill", "character.bubble", "character.book.closed.fill", "person.2.fill", "globe.americas.fill"], id: \.self) { symbol in Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(symbol == "character.book.closed.fill" ? Color.purple : Color.secondary.opacity(0.6)).frame(width: 24, height: 19).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5)) } }
    }
    private func displayName(_ model: Model) -> String {
        switch model.id { case "whisper-large-v3": return "Whisper Large"; case "whisper-large-v3-turbo": return "Whisper Large v3 Turbo"; case "whisper-medium": return "Whisper Medium"; case "whisper-small", "whisper-small.en": return "Whisper Small"; default: return model.name.replacingOccurrences(of: ".en", with: "") }
    }
    private func providerName(_ model: Model) -> String {
        switch model.engine { case "cloud": return model.cloudProvider?.title ?? "Cloud"; case "parakeet", "canary": return "NVIDIA"; case "sherpa": return "ONNX"; case "apple": return "Apple"; default: return "OpenAI" }
    }
    private func engineDescription(_ model: Model) -> String {
        if model.id == "whisper-large-v3-turbo" { return "Best offline accuracy, optimized for speed. Formerly \"Superwhisper Ultra V3 Turbo\"." }
        switch model.engine { case "cloud": return "Transcribes audio using your cloud provider."; case "parakeet", "canary": return "Fast on-device speech recognition."; case "sherpa": return "Speech recognition that runs offline."; case "apple": return "On-device speech recognition using Apple Speech."; default: return "Accurate speech recognition that runs offline." }
    }
    private func provider(_ model: Model) -> some View { ProviderMark(name: providerName(model)).frame(width: 20, height: 20) }
    private func ratings(_ model: Model) -> some View { VStack(alignment: .leading, spacing: 4) { rating(model.speed); rating(model.accuracy) } }
    private func rating(_ value: Int?, detail: Bool = false) -> some View { HStack(spacing: detail ? 4 : 2) { ForEach(0..<5) { i in Capsule().fill(i < (value ?? 0) ? Color.primary.opacity(0.38) : Color.primary.opacity(0.09)).frame(width: detail ? 18 : 15, height: detail ? 4 : 2) } } }
    private func size(_ model: Model) -> String { guard let value = model.size else { return "—" }; if value >= 1_000_000_000 { return String(format: "%.1f GB", Double(value) / 1_000_000_000) }; if value >= 100_000_000 { return "\(Int((Double(value) / 50_000_000).rounded()) * 50) MB" }; return ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func action(_ model: Model) -> some View { Button { if ModelStore.exists(model) { ui.deleting = model } else { controller.download(model) } } label: { Image(systemName: ModelStore.exists(model) ? "trash.fill" : "arrow.down").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 21, height: 21).background(ModelStore.exists(model) ? Color.primary.opacity(0.08) : .clear, in: Circle()).overlay(Circle().stroke(ModelStore.exists(model) ? .clear : Color.primary.opacity(0.35), lineWidth: 1)) }.buttonStyle(.plain).disabled(controller.busyModel != nil).help(ModelStore.exists(model) ? "Delete" : "Download") }
    private func toggleFavorite(_ model: Model) { var ids = favoriteIDs; if !ids.insert(model.id).inserted { ids.remove(model.id) }; favorites = ids.sorted().joined(separator: ",") }
}

private struct ProviderMark: View {
    let name: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(name == "NVIDIA" ? Color(red: 130/255, green: 181/255, blue: 47/255) : Color.gray.opacity(0.65))
            if name == "OpenAI" { ForEach(0..<6) { i in Capsule().stroke(Color.white, lineWidth: 0.8).frame(width: 7, height: 13).offset(y: -2).rotationEffect(.degrees(Double(i) * 60)) } }
            else { Image(systemName: name == "NVIDIA" ? "eye" : name == "Apple" ? "apple.logo" : name == "Cloud" ? "cloud.fill" : "waveform").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white) }
        }
    }
}
private struct CircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28).background(Color.primary.opacity(configuration.isPressed ? 0.17 : 0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)) }
}
private struct DestructiveFooterButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 28).background(Color.red.opacity(configuration.isPressed ? 0.75 : 0.9), in: RoundedRectangle(cornerRadius: 6)) }
}
private struct FooterButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).frame(height: 28).background(Color.primary.opacity(configuration.isPressed ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 6)) }
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
                Text("sherpa-onnx Moonshine v2").tag("sherpa:moonshine_v2")
                Text("sherpa-onnx Qwen3 ASR").tag("sherpa:qwen3")
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

private final class CloudSheetState: ObservableObject {
    @Published var provider: CloudProvider = .groq
    @Published var model = "whisper-large-v3-turbo"
    @Published var endpoint = ""
    @Published var key = ""
    @Published var fallback = ""
    @Published var error = ""
}
private struct CloudModelSheet: View {
    @ObservedObject var controller: AppController
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = CloudSheetState()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring your own key").font(.headline)
            Text("Audio is sent to the selected provider for transcription. Free-tier limits depend on your account.").foregroundStyle(.secondary)
            if state.provider == .gemini { Text("Google may use free-tier content to improve its products.").font(.caption).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $state.provider) { ForEach(CloudProvider.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .onChange(of: state.provider) { provider in state.model = provider.models.first ?? "" }
                if state.provider == .compatible {
                    TextField("Base URL (https://…/v1)", text: $state.endpoint)
                    TextField("Model name", text: $state.model)
                } else { Picker("Model", selection: $state.model) { ForEach(state.provider.models, id: \.self) { Text($0).tag($0) } } }
                SecureField("API key", text: $state.key)
                Picker("Offline fallback", selection: $state.fallback) {
                    Text("None").tag("")
                    ForEach(controller.models.filter { $0.engine != "cloud" && ModelStore.exists($0) }) { Text($0.name).tag($0.id) }
                }
            }.textFieldStyle(.roundedBorder).padding(16).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            if !state.error.isEmpty { Text(state.error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Add model") { do { try controller.addCloudModel(provider: state.provider, name: state.model, address: state.endpoint, key: state.key, fallbackID: state.fallback.isEmpty ? nil : state.fallback); state.key = ""; dismiss() } catch { state.error = error.localizedDescription } }.disabled(state.key.isEmpty || state.model.isEmpty) }
        }.padding(24).frame(width: 460)
    }
}

private struct CanaryLanguagePicker: View {
    let model: Model
    @ObservedObject var controller: AppController
    @AppStorage private var language: String
    init(model: Model, controller: AppController) { self.model = model; self.controller = controller; _language = AppStorage(wrappedValue: "en", "canaryLanguage." + model.id) }
    var body: some View {
        Picker("Transcription language", selection: $language) {
            ForEach(model.version == "nemo_canary" ? ["en", "es", "de", "fr"] : ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it", "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk"], id: \.self) { code in Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code) }
        }.onChange(of: language) { _ in controller.reloadSelectedModel() }
    }
}
