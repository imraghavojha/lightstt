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
    @Published var sortColumn = ""
    @Published var ascending = true
    @Published var installed: Set<String>?
    @Published var visible: [Model] = []
    var scanGeneration = 0
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
    @Binding var deleting: Model?
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("selectedModel") private var selectedModel = "whisper-tiny.en"
    @AppStorage("favoriteModels") private var favorites = "whisper-large-v3,whisper-large-v3-turbo,whisper-medium,whisper-small,whisper-small.en"
    @StateObject private var ui = ModelsPageState()

    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }
    private func rebuildVisible() {
        let start = ProcessInfo.processInfo.systemUptime
        let preferred = ["whisper-large-v3", "whisper-large-v3-turbo", "whisper-medium", "whisper-small", "whisper-small.en"]
        ui.visible = controller.models.filter { (ui.query.isEmpty || $0.name.localizedCaseInsensitiveContains(ui.query) || displayName($0).localizedCaseInsensitiveContains(ui.query)) && (!ui.installedOnly || (ui.installed?.contains($0.id) ?? false)) }.sorted { a, b in
            if !ui.sortColumn.isEmpty {
                let comparison: ComparisonResult
                switch ui.sortColumn {
                case "Type": comparison = .orderedSame // All entries currently represent voice models.
                case "Speed / Accuracy": comparison = (speed(a) ?? 0) == (speed(b) ?? 0) ? compare(accuracy(a) ?? 0, accuracy(b) ?? 0) : compare(speed(a) ?? 0, speed(b) ?? 0)
                case "Cloud/Offline": comparison = a.engine == b.engine || (a.engine != "cloud" && b.engine != "cloud") ? compare(a.size ?? 0, b.size ?? 0) : (a.engine == "cloud" ? .orderedAscending : .orderedDescending)
                default: comparison = displayName(a).localizedStandardCompare(displayName(b))
                }
                if comparison != .orderedSame { return ui.ascending ? comparison == .orderedAscending : comparison == .orderedDescending }
                return a.id < b.id
            }
            let x = preferred.firstIndex(of: a.id) ?? preferred.count
            let y = preferred.firstIndex(of: b.id) ?? preferred.count
            return x == y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x < y
        }
        UITrace.duration("models-filter-sort-\(controller.models.count)", since: start)
    }
    private func refreshInstalled() {
        ui.scanGeneration += 1
        let generation = ui.scanGeneration
        let models = controller.models
        DispatchQueue.global(qos: .userInitiated).async {
            let installed = Set(models.filter { ModelStore.exists($0) }.map(\.id))
            DispatchQueue.main.async {
                guard generation == ui.scanGeneration else { return }
                ui.installed = installed
                rebuildVisible()
            }
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
                        if !ui.query.isEmpty { Button { ui.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Clear search") }
                    }.font(.system(size: 13)).padding(.horizontal, 10).frame(width: 220, height: 28).background(LinearGradient(stops: colorScheme == .dark ? [
                        .init(color: Color(red: 74/255, green: 74/255, blue: 82/255), location: 0),
                        .init(color: Color(red: 68/255, green: 69/255, blue: 74/255), location: 0.35),
                        .init(color: Color(red: 69/255, green: 72/255, blue: 79/255), location: 0.75),
                        .init(color: Color(red: 76/255, green: 79/255, blue: 86/255), location: 1)
                    ] : [
                        .init(color: Color(white: 249/255), location: 0),
                        .init(color: Color(white: 241/255), location: 0.35),
                        .init(color: Color(white: 245/255), location: 0.75),
                        .init(color: Color(white: 250/255), location: 1)
                    ], startPoint: .top, endPoint: .bottom), in: Capsule()).overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.5)).overlay(Capsule().stroke(Color.white.opacity(colorScheme == .light ? 0.65 : 0.10), lineWidth: 0.5).padding(1))
                } else { Button { ui.searching = true } label: { Image(systemName: "magnifyingglass") }.buttonStyle(CircleButton()).help("Search") }
                Menu { Toggle("Downloaded only", isOn: $ui.installedOnly) } label: { toolbarIcon("line.3.horizontal.decrease") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)).help("Filters")
                Menu { Button("Add cloud model…") { ui.cloud = true }; Button("Add local model…") { ui.custom = true } } label: { Color.clear.frame(width: 20, height: 20) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).overlay { Image(nsImage: keyPlusImage).renderingMode(.template).foregroundColor(colorScheme == .dark ? Color(red: 208/255, green: 209/255, blue: 210/255) : Color(red: 109/255, green: 109/255, blue: 109/255)).allowsHitTesting(false) }.background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)).help("Bring your own key")
            }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            library
            if !controller.message.isEmpty { Text(controller.message).font(.caption).foregroundStyle(.red).padding(.horizontal, 20).padding(.bottom, 8) }
        }
        .background(colorScheme == .dark ? Color(red: 44/255, green: 47/255, blue: 52/255) : Color(red: 242/255, green: 242/255, blue: 242/255))
        .overlay { if ui.detail != nil { (colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.35)).allowsHitTesting(false) } }
        .overlay(alignment: .trailing) {
            if let model = ui.detail {
                detailView(model).frame(width: 400).frame(maxHeight: .infinity)
                    .background(LinearGradient(colors: colorScheme == .dark ? [Color(red: 43/255, green: 49/255, blue: 57/255), Color(red: 35/255, green: 43/255, blue: 52/255)] : [Color(red: 235/255, green: 237/255, blue: 240/255), Color(red: 225/255, green: 229/255, blue: 234/255)], startPoint: .top, endPoint: .bottom))
                    .background(alignment: .leading) { Rectangle().fill(Color.black.opacity(colorScheme == .dark ? 0.3 : 0.14)).frame(width: 1).shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 12, x: -5).offset(x: -1) }
            }
        }
        .task { rebuildVisible(); refreshInstalled(); await ModelStore.refreshAppleStatus() }
        .onChange(of: controller.models) { _ in rebuildVisible(); refreshInstalled() }
        .onChange(of: controller.busyModel) { _ in refreshInstalled() }
        .onChange(of: deleting?.id) { _ in if deleting == nil { refreshInstalled() } }
        .onChange(of: ui.query) { _ in rebuildVisible() }
        .onChange(of: ui.installedOnly) { _ in rebuildVisible() }
        .onChange(of: ui.sortColumn) { _ in rebuildVisible() }
        .onChange(of: ui.ascending) { _ in rebuildVisible() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await ModelStore.refreshAppleStatus(); refreshInstalled() } }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in Task { await ModelStore.refreshAppleStatus(); refreshInstalled() } }
        .sheet(isPresented: $ui.custom) { CustomModelSheet(controller: controller) }
        .sheet(isPresented: $ui.cloud) { CloudModelSheet(controller: controller, installed: ui.installed ?? []) }
    }
    private static let keyPlusImage: NSImage = {
        let image = NSImage(contentsOf: Bundle.module.url(forResource: "key-plus", withExtension: "png")!)!
        image.isTemplate = true
        image.size = NSSize(width: 20, height: 20)
        return image
    }()
    private var keyPlusImage: NSImage { Self.keyPlusImage }
    private func toolbarIcon(_ name: String, plus: Bool = false) -> some View {
        ZStack(alignment: .topTrailing) {
            if plus {
                Image(nsImage: keyPlusImage).resizable().frame(width: 28, height: 28)
            } else { Image(systemName: name).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28) }
        }.background(Color.primary.opacity(0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
    private var library: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let compact = width < 540
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    sortHeader("Model name").frame(maxWidth: .infinity, alignment: .leading)
                    sortHeader("Type").frame(width: compact ? 30 : 42, alignment: .leading)
                    sortHeader("Speed / Accuracy").lineLimit(1).minimumScaleFactor(0.75).frame(width: compact ? 85 : 110, alignment: .leading)
                    sortHeader("Cloud/Offline").frame(width: 90, alignment: .trailing)
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(colorScheme == .dark ? Color(red: 118/255, green: 120/255, blue: 123/255) : Color(red: 76/255, green: 76/255, blue: 76/255)).padding(.leading, 56).padding(.trailing, compact ? 18 : 28).padding(.top, 20).padding(.bottom, 8)
                ScrollView { LazyVStack(spacing: 0) { ForEach(ui.visible) { model in
                    HStack(spacing: 8) {
                        Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star").foregroundStyle(Color.secondary).frame(width: 24) }.buttonStyle(.plain)
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
                        .background { if ui.detail?.id == model.id { RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.10)).padding(.horizontal, 24) } }
                } }.frame(width: width) }
            }
        }
    }
    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult { a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending) }
    private func sortHeader(_ title: String) -> some View {
        Button { if ui.sortColumn == title { ui.ascending.toggle() } else { ui.sortColumn = title; ui.ascending = true } } label: { HStack(spacing: 3) { Text(title); if ui.sortColumn == title || (ui.sortColumn.isEmpty && title == "Model name") { Image(systemName: ui.ascending ? "chevron.up" : "chevron.down").font(.system(size: 8)) } } }.buttonStyle(.plain)
    }
    private var progressButton: some View {
        Button { controller.cancelDownload() } label: {
            ZStack { Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1.5); Circle().fill(Color.primary.opacity(0.08)).padding(3); Circle().trim(from: 0, to: min(max(controller.downloadProgress, 0), 1)).stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).rotationEffect(.degrees(-90)); Image(systemName: "xmark").font(.system(size: 8, weight: .semibold)) }.frame(width: 22, height: 22)
        }.buttonStyle(.plain).help("Cancel download")
    }
    private func detailView(_ model: Model) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button { ui.detail = nil } label: { Image(systemName: "chevron.left").font(.system(size: 12)) }.buttonStyle(.plain).frame(width: 20, height: 28).offset(y: -4)
                Spacer(); provider(model).offset(y: -9)
                VStack(alignment: .leading, spacing: 1) { Text(displayName(model)).font(.system(size: 13, weight: .bold)); Text(subtitle(model)).font(.system(size: 10)).foregroundStyle(.secondary) }.offset(y: -4)
                Spacer(); Button { toggleFavorite(model) } label: { Image(systemName: favoriteIDs.contains(model.id) ? "star.fill" : "star").foregroundStyle(.secondary) }.buttonStyle(.plain).offset(y: -4)
            }
            Text(engineDescription(model)).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack { Text("Type"); Spacer(); Text("Voice model").foregroundStyle(.primary) }.frame(height: 31)
                HStack { Text("Specs"); Spacer(); specs(model) }.frame(height: 31)
                HStack { Text("Speed"); Spacer(); rating(speed(model), detail: true) }.frame(height: 31)
                HStack { Text("Accuracy"); Spacer(); rating(accuracy(model), detail: true) }.frame(height: 31)
                HStack { Text("Size"); Spacer(); Text(model.engine == "cloud" ? "Cloud" : size(model)).foregroundStyle(.primary) }.frame(height: 31)
            }.foregroundStyle(.secondary).font(.system(size: 13)).padding(.horizontal, 16).padding(.vertical, 8).background(LinearGradient(colors: colorScheme == .dark ? [Color(red: 52/255, green: 57/255, blue: 65/255), Color(red: 48/255, green: 54/255, blue: 62/255)] : [Color(red: 224/255, green: 227/255, blue: 231/255), Color(red: 216/255, green: 221/255, blue: 227/255)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 16))
            if model.engine == "canary" || model.version == "nemo_canary" { CanaryLanguagePicker(model: model, controller: controller) }
            else if let languages = model.languages { Text(languages.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            HStack(spacing: 8) {
                if ui.installed?.contains(model.id) == true {
                    Button(selectedModel == model.id ? "Selected" : "Use in all modes") { selectedModel = model.id; controller.reloadSelectedModel() }.buttonStyle(FooterButton()).disabled(selectedModel == model.id)
                    Button { deleting = model } label: { Image(systemName: "trash.fill").frame(width: 28, height: 28).background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
                } else if controller.busyModel == model.id { Text("Downloading \(Int(controller.downloadProgress * 100))%"); Spacer(); progressButton }
                else { Button("Download · \(size(model))") { controller.download(model) }.buttonStyle(FooterButton()).disabled(controller.busyModel != nil || ui.installed == nil) }
            }
        }.font(.system(size: 12)).padding(16)
    }
    private func specs(_ model: Model) -> some View {
        HStack(spacing: 5) { ForEach(["bolt.fill", "translate", "character.book.closed.fill", "person.2.fill", "globe.americas.fill"], id: \.self) { symbol in
            let active = (symbol == "translate" && ["whisper-tiny", "whisper-medium"].contains(model.id)) || (symbol == "character.book.closed.fill" && ["whisper-medium", "whisper-large-v3-turbo"].contains(model.id))
            let hue = symbol == "translate"
                ? (colorScheme == .dark ? Color(red: 60/255, green: 181/255, blue: 247/255) : Color(red: 58/255, green: 174/255, blue: 238/255))
                : (colorScheme == .dark ? Color(red: 157/255, green: 129/255, blue: 252/255) : Color(red: 106/255, green: 76/255, blue: 208/255))
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(active ? hue : Color.secondary.opacity(0.6)).frame(width: 24, height: 19).background(active ? hue.opacity(colorScheme == .dark ? 0.10 : 0.08) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        } }
    }
    private func subtitle(_ model: Model) -> String { switch model.id { case "whisper-large-v3-turbo": return "Superwhisper Ultra V3 Turbo"; case "whisper-medium": return "Superwhisper Pro"; case "whisper-tiny": return "Superwhisper Fast"; default: return providerName(model) } }
    private func speed(_ model: Model) -> Int? { switch model.id { case "whisper-large-v3": return 3; case "whisper-small", "whisper-small.en": return 4; default: return model.speed } }
    private func accuracy(_ model: Model) -> Int? { switch model.id { case "whisper-large-v3": return 5; case "whisper-medium": return 4; case "whisper-small", "whisper-small.en": return 2; default: return model.accuracy } }
    private func displayName(_ model: Model) -> String {
        switch model.id { case "whisper-large-v3": return "Whisper Large"; case "whisper-large-v3-turbo": return "Whisper Large v3 Turbo"; case "whisper-medium": return "Whisper Medium"; case "whisper-small", "whisper-small.en": return "Whisper Small"; case "whisper-tiny", "whisper-tiny.en": return "Whisper Tiny"; default: return model.name.replacingOccurrences(of: ".en", with: "") }
    }
    private func providerName(_ model: Model) -> String {
        switch model.engine { case "cloud": return model.cloudProvider?.title ?? "Cloud"; case "parakeet", "canary": return "NVIDIA"; case "sherpa": return "ONNX"; case "apple": return "Apple"; default: return "OpenAI" }
    }
    private func engineDescription(_ model: Model) -> String {
        if model.id == "whisper-medium" { return "High multilingual accuracy, with slower transcription. Formerly \"Superwhisper Pro\"." }
        if model.id == "whisper-tiny" { return "Fastest Whisper model, with basic accuracy. Formerly \"Superwhisper Fast\"." }
        if model.id == "whisper-large-v3-turbo" { return "Best offline accuracy, optimized for speed. Formerly \"Superwhisper Ultra V3 Turbo\"." }
        switch model.engine { case "cloud": return "Transcribes audio using your cloud provider."; case "parakeet", "canary": return "Fast on-device speech recognition."; case "sherpa": return "Speech recognition that runs offline."; case "apple": return "On-device speech recognition using Apple Speech."; default: return "Accurate speech recognition that runs offline." }
    }
    private func provider(_ model: Model) -> some View { ProviderMark(name: providerName(model)).frame(width: 20, height: 20) }
    private func ratings(_ model: Model) -> some View { VStack(alignment: .leading, spacing: 4) { rating(speed(model)); rating(accuracy(model)) } }
    private func rating(_ value: Int?, detail: Bool = false) -> some View { HStack(spacing: detail ? 4 : 2) { ForEach(0..<5) { i in Capsule().fill(i < (value ?? 0) ? Color.primary.opacity(0.38) : Color.primary.opacity(0.09)).frame(width: detail ? 18 : 15, height: detail ? 4 : 2) } } }
    private func size(_ model: Model) -> String { guard let value = model.size else { return "—" }; if model.id == "whisper-large-v3" { return "3 GB" }; if ["whisper-tiny", "whisper-tiny.en"].contains(model.id) { return "75 MB" }; if ["whisper-small", "whisper-small.en"].contains(model.id) { return "500 MB" }; if value >= 1_000_000_000 { return String(format: "%.1f GB", Double(value) / 1_000_000_000) }; return ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func action(_ model: Model) -> some View {
        let installed = ui.installed?.contains(model.id) == true
        return Button { if installed { deleting = model } else { controller.download(model) } } label: {
            Image(systemName: installed ? "trash.fill" : "arrow.down").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 15, height: 15).background(installed ? Color.clear : Color.primary.opacity(0.07), in: Circle()).frame(width: 21, height: 21).background(installed ? Color.primary.opacity(0.08) : .clear, in: Circle()).overlay(Circle().stroke(installed ? .clear : Color.primary.opacity(0.35), lineWidth: 1))
        }.buttonStyle(.plain).disabled(controller.busyModel != nil || ui.installed == nil).help(installed ? "Delete" : "Download")
    }
    private func toggleFavorite(_ model: Model) { var ids = favoriteIDs; if !ids.insert(model.id).inserted { ids.remove(model.id) }; favorites = ids.sorted().joined(separator: ",") }
}

private struct ProviderMark: View {
    private static let openAI = NSImage(contentsOf: Bundle.module.url(forResource: "openai", withExtension: "png")!)!
    private static let nvidia = NSImage(contentsOf: Bundle.module.url(forResource: "nvidia", withExtension: "png")!)!
    let name: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(name == "NVIDIA" ? Color(red: 130/255, green: 181/255, blue: 47/255) : Color(red: 83/255, green: 86/255, blue: 90/255))
            if name == "OpenAI" || name == "NVIDIA" { Image(nsImage: name == "OpenAI" ? Self.openAI : Self.nvidia).resizable().aspectRatio(contentMode: .fit).frame(width: 15, height: 15) }
            else { Image(systemName: name == "NVIDIA" ? "eye" : name == "Apple" ? "apple.logo" : name == "Cloud" ? "cloud.fill" : "waveform").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white) }
        }
    }
}

private struct CircleButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28).background(Color.primary.opacity(configuration.isPressed ? 0.17 : 0.07), in: Circle()).overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5)) }
}
private struct DestructiveFooterButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .medium)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 28).background(Color.red.opacity(configuration.isPressed ? 0.75 : 0.9), in: RoundedRectangle(cornerRadius: 6)) }
}
private struct FooterButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 13, weight: .regular)).frame(maxWidth: .infinity).frame(height: 28).background(Color.primary.opacity(configuration.isPressed ? 0.20 : 0.12), in: RoundedRectangle(cornerRadius: 6)) }
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
    let installed: Set<String>
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = CloudSheetState()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bring your own key").font(.headline)
            Text("Audio is sent to the selected provider for transcription. Free-tier limits depend on your account.").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if state.provider == .gemini { Text("Google may use free-tier content to improve its products.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Provider").frame(width: 110, alignment: .leading); Picker("Provider", selection: $state.provider) { ForEach(CloudProvider.allCases, id: \.self) { Text($0.title).tag($0) } }
                    .labelsHidden().frame(maxWidth: .infinity).onChange(of: state.provider) { provider in state.model = provider.models.first ?? "" } }
                if state.provider == .compatible {
                    TextField("Base URL (https://…/v1)", text: $state.endpoint)
                    TextField("Model name", text: $state.model)
                } else { HStack { Text("Model").frame(width: 110, alignment: .leading); Picker("Model", selection: $state.model) { ForEach(state.provider.models, id: \.self) { Text($0 == "gemini-2.5-flash" ? "\($0) (legacy)" : $0).tag($0) } }.labelsHidden().frame(maxWidth: .infinity) } }
                SecureField("API key", text: $state.key)
                HStack { Text("Offline fallback").frame(width: 110, alignment: .leading); Picker("Offline fallback", selection: $state.fallback) {
                    Text("None").tag("")
                    ForEach(controller.models.filter { $0.engine != "cloud" && installed.contains($0.id) }) { Text($0.name).tag($0.id) }
                }.labelsHidden().frame(maxWidth: .infinity) }
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
