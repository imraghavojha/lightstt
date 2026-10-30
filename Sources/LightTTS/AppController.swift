import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import CryptoKit
import LightTTSCore
import Darwin

@MainActor final class AppController: NSObject, ObservableObject {
    @Published var state = "idle"
    @Published var settingsSelection = "Sound"
    @Published var level: Float = 0
    @Published var started = Date()
    @Published var message = ""
    @Published var history: [HistoryEntry] = []
    @Published var models: [Model] = []
    @Published var busyModel: String?
    @Published var downloadProgress: Double = 0
    var onCatalogReady: (() -> Void)?
    private var downloadTask: Task<Void, Never>?
    private var engine: (any TranscriptionEngine)?
    private var unloadTimer: Timer?
    private var loadedID = ""
    private var warmingID = ""
    private var warmingToken = UUID()
    private var warming: Task<any TranscriptionEngine, Error>?
    private(set) var audio: AudioCapture?
    private var panel: NSPanel?
    private let hotkey = HotkeyMonitor()
    private var processing: Task<Void, Never>?
    private var focus: FocusTarget?
    private var sessionAutoPaste = true
    private var testAudio: [Float]?
    private var defaultsObserver: NSObjectProtocol?
    private var pressed = false
    private var generation = 0
    private let historyURL = ModelStore.directory.deletingLastPathComponent().appendingPathComponent("history.json")
    override init() {
        super.init()
        let historyURL = self.historyURL
        Task {
            let data = await Task.detached(priority: .utility) { () -> ([Model], [HistoryEntry]) in
                let catalog = (try? ModelCatalog.load()) ?? []
                let custom = UserDefaults.standard.data(forKey: "customModels").flatMap { try? JSONDecoder().decode([Model].self, from: $0) } ?? []
                let history = (try? Data(contentsOf: historyURL)).flatMap { try? JSONDecoder().decode([HistoryEntry].self, from: $0) } ?? []
                return (catalog + custom, Array(history.prefix(500)))
            }.value
            self.models = data.0; self.history = data.1; LaunchTrace.mark("catalog-ready"); self.onCatalogReady?()
            await ModelStore.refreshAppleStatus(); self.objectWillChange.send()
        }
        if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { showPanel() }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == "idle", ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_STATE"] == nil else { return }
                if !self.keepModelLoaded && (self.engine != nil || self.warming != nil) { self.unloadEngine() }
                if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { self.showPanel() } else { self.dismissPanel() }
            }
        }
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testToggle(_:)), name: Notification.Name("com.lighttts.test.toggle.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testHIDShortcut(_:)), name: Notification.Name("com.lighttts.test.hid.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        #endif
    }
    #if DEBUG
    func testURLToggle() { handleShortcut(true); handleShortcut(false) }
    @objc private func testToggle(_ notification: Notification) { testURLToggle() }
    @objc private func testHIDShortcut(_ notification: Notification) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            if let event = CGEvent(keyboardEventSource: source, virtualKey: 49, keyDown: down) { event.flags = .maskAlternate; event.post(tap: .cghidEventTap) }
        }
    }
    #endif
    func warmSelected() {
        let selected = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_MODEL"] ?? UserDefaults.standard.string(forKey: "selectedModel") ?? "whisper-tiny.en"
        guard selected != loadedID, selected != warmingID, let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { return }
        warming?.cancel()
        warmingID = selected; warmingToken = UUID()
        let token = warmingToken
        let onCrash: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.warmingToken == token else { return }
                self.fail("Speech engine exited unexpectedly. Try recording again.")
            }
        }
        let task = Task.detached(priority: .utility) { () -> any TranscriptionEngine in
            try await HelperEngine.load(model, onCrash: onCrash)
        }
        warming = task
        if state == "idle" || state == "error" { scheduleEngineUnload() }
        Task { [weak self] in
            do { _ = try await task.value }
            catch { guard let self, self.warmingToken == token else { return }; self.warming = nil; self.warmingID = ""; if !(error is CancellationError) { self.fail(error.localizedDescription) } }
        }
    }
    func reloadSelectedModel() {
        warming?.cancel(); warming = nil; warmingID = ""; warmingToken = UUID()
        engine = nil; loadedID = ""; warmSelected()
    }
    @discardableResult func installHotkey() -> Bool {
        hotkey.onShortcut = { [weak self] down in self?.handleShortcut(down) }
        hotkey.onEscape = { [weak self] in if self?.state != "idle" { self?.cancel() } }
        let installed = hotkey.install()
        if !installed { message = "Enable Accessibility and Input Monitoring in System Settings, then retry the shortcut." }
        return installed
    }
    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        _ = CGRequestListenEventAccess()
        installHotkey()
    }
    func handleShortcut(_ down: Bool) {
        if down && !pressed {
            pressed = true
            if state == "error" { cancel() }
            if UserDefaults.standard.bool(forKey: "pushToTalk") { start() }
            else if state == "starting" { cancel() }
            else if state == "recording" { stop() }
            else if state == "idle" { start() }
        } else if !down && pressed {
            pressed = false
            if UserDefaults.standard.bool(forKey: "pushToTalk") {
                if state == "starting" { cancel() } else if state == "recording" { stop() }
            }
        }
    }
    func start() {
        guard state == "idle" else { return }
        unloadTimer?.invalidate(); unloadTimer = nil
        generation += 1; let current = generation
        state = "starting"
        warmSelected()
        sessionAutoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        focus = nil
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_PASTE"] != "1" {
            do {
                let capture = AudioCapture { [weak self] value in Task { @MainActor in self?.level = value } }
                try capture.start(); audio = capture; started = Date(); state = "recording"; showPanel()
            } catch { fail(error.localizedDescription) }
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        Task {
            if sessionAutoPaste {
                let target = await Task.detached(priority: .userInitiated) { FocusTarget.capture(frontPID: frontPID) }.value
                guard current == generation, state == "starting", !UserDefaults.standard.bool(forKey: "pushToTalk") || pressed else { return }
                guard let target else { fail("Focus a text field and check Accessibility access before recording."); return }
                focus = target
            }
            if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil {
                do {
                    let capture = AudioCapture { [weak self] value in Task { @MainActor in self?.level = value } }
                    try capture.start(); audio = capture; started = Date(); state = "recording"; showPanel()
                } catch { fail(error.localizedDescription) }
                return
            }
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? ProcessInfo.processInfo.environment["LIGHTTTS_TEST_WAV"] {
                do { testAudio = try AudioFileReader.read(URL(fileURLWithPath: path)); started = Date(); state = "recording"; showPanel() } catch { fail(error.localizedDescription) }
                return
            }
            #endif
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard current == generation, state == "starting", !UserDefaults.standard.bool(forKey: "pushToTalk") || pressed else { return }
            guard allowed else { fail("Microphone access is required. Enable it in System Settings."); return }
            do {
                let capture = AudioCapture { [weak self] value in Task { @MainActor in self?.level = value } }
                try capture.start(); audio = capture; started = Date(); state = "recording"; showPanel()
            } catch { fail(error.localizedDescription) }
        }
    }
    func stop() {
        guard state == "recording" else { return }
        LaunchTrace.mark("recording-stopped")
        let samples = testAudio ?? audio?.stop() ?? []
        testAudio = nil; audio = nil; state = "processing"; let current = generation
        processing = Task {
            do {
                let selected = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_MODEL"] ?? UserDefaults.standard.string(forKey: "selectedModel") ?? "whisper-tiny.en"
                guard let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { throw SpeechError.model("Download a model in Models settings first.") }
                if loadedID != selected || engine == nil {
                    warmSelected()
                    let token = warmingToken
                    let resolved: any TranscriptionEngine
                    do {
                        if warmingID == selected, let warming { resolved = try await warming.value }
                        else { resolved = try await HelperEngine.load(model) }
                    } catch { if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }; throw error }
                    if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }
                    try Task.checkCancellation(); guard current == generation else { return }
                    engine = resolved; loadedID = selected
                }
                guard engine != nil else { return }
                try Task.checkCancellation(); guard current == generation else { return }
                let text = try await engine!.transcribe(samples: samples)
                guard current == generation else { return }
                if !keepModelLoaded { unloadEngine() }
                guard !text.isEmpty else { throw SpeechError.audio("No speech detected.") }
                if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_PASTE"] != "1" {
                    print("LIGHTTTS_TEST transcription completed, samples: \(samples.count)")
                    state = "done"
                    try? await Task.sleep(nanoseconds: 1_000_000_000); if current == generation { hide() }
                    return
                }
                if sessionAutoPaste {
                    guard AXIsProcessTrusted() else { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); throw SpeechError.audio("Allow Accessibility access in System Settings to paste text.") }
                    guard let target = focus else { throw SpeechError.audio("The focused field is unavailable.") }
                    try await Task.detached(priority: .userInitiated) { try target.insert(text) }.value
                } else {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                }
                try Task.checkCancellation(); guard current == generation else { return }
                LaunchTrace.mark("text-inserted")
                history.insert(HistoryEntry(text: text, date: Date()), at: 0); if history.count > 500 { history.removeLast(history.count - 500) }; saveHistory(); state = "done"
                try? await Task.sleep(nanoseconds: 1_000_000_000); if current == generation { hide() }
            } catch { if current == generation { fail(error.localizedDescription) } }
        }
    }
    func cancel() { generation += 1; processing?.cancel(); processing = nil; _ = audio?.stop(); audio = nil; testAudio = nil; unloadEngine(); hide() }
    private func hide() {
        state = "idle"; level = 0
        scheduleEngineUnload()
        if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { showPanel() }
        else if let panel {
            let current = generation
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; panel.animator().alphaValue = 0 } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, self.generation == current, self.state == "idle", !UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") else { return }
                    panel?.orderOut(nil)
                    if self.panel === panel { self.panel = nil }
                }
            }
        }
    }
    func showPreviewState(_ previewState: String) { state = previewState; message = "Microphone access is required."; level = 0; showPanel() }
    private func dismissPanel() {
        panel?.orderOut(nil)
        panel = nil
    }
    private var keepModelLoaded: Bool {
        UserDefaults.standard.object(forKey: "keepModelLoaded") as? Bool ?? true
    }
    private func unloadEngine() {
        unloadTimer?.invalidate(); unloadTimer = nil
        warmingToken = UUID(); warming?.cancel(); warming = nil; warmingID = ""
        (engine as? HelperEngine)?.terminate()
        engine = nil; loadedID = ""
    }
    // One coalescible, non-repeating timer only while a model is resident or loading.
    // Set modelIdleTimeoutSeconds in defaults to change the two-minute default.
    private func scheduleEngineUnload() {
        unloadTimer?.invalidate(); unloadTimer = nil
        guard engine != nil || warming != nil else { return }
        guard keepModelLoaded else { unloadEngine(); return }
        let configured = UserDefaults.standard.object(forKey: "modelIdleTimeoutSeconds") as? Double ?? 120
        let interval = max(1, configured)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == "idle" || self.state == "error" else { return }
                self.unloadEngine()
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        unloadTimer = timer
    }
    func fail(_ text: String) {
        generation += 1; processing?.cancel(); processing = nil
        _ = audio?.stop(); audio = nil; testAudio = nil; focus = nil; level = 0
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS error: \(text)\n", stderr) }
        unloadEngine(); message = text; state = "error"; showPanel()
    }
    private func showPanel() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = NSWindow.Level(rawValue: 27); p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.contentView = NSHostingView(rootView: RecordingView(controller: self)); panel = p
        }
        if let frame = NSScreen.main?.visibleFrame, let p = panel { p.setFrameOrigin(NSPoint(x: frame.midX - p.frame.width / 2, y: frame.minY + 70));
            if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless(); NSAnimationContext.runAnimationGroup { context in context.duration = 0.15; p.animator().alphaValue = 1 } }
            else { p.alphaValue = 1 } }
    }
    private func saveHistory() { try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(history) { try? data.write(to: historyURL, options: .atomic) } }
    func importLocalModel(engine: String = "whisper", version: String = "") {
        let panel = NSOpenPanel(); panel.canChooseDirectories = engine != "whisper"; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = "custom-" + UUID().uuidString
        do {
            var model = Model(id: id, name: url.lastPathComponent, engine: engine, version: version.isEmpty ? nil : version)
            if engine == "whisper" { try ModelStore.importFile(url, id: id) }
            else {
                let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                let source = isDirectory && !url.lastPathComponent.hasSuffix(".mlmodelc") ? url : url.deletingLastPathComponent()
                if engine == "sherpa" { model.files = try SherpaModelFiles.requiredFiles(version).map { ModelFile(path: $0, url: source.appendingPathComponent($0), size: 0, sha256: "") } }
                try ModelStore.importDirectory(source, model: model)
            }
            addCustom(model)
        } catch { message = error.localizedDescription }
    }
    func importRemoteModel(_ address: String, sha256: String) {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String
        if !input.contains("://"), input.split(separator: "/").count == 2 {
            resolved = "https://huggingface.co/\(input)/resolve/main/ggml-model.bin"
        } else { resolved = input }
        guard let url = URL(string: resolved), url.scheme?.lowercased() == "https" else { message = "Enter a valid HTTPS model URL or Hugging Face owner/repository."; return }
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { message = "Enter the model SHA-256."; return }
        let model = Model(id: "custom-" + UUID().uuidString, name: url.lastPathComponent, engine: "whisper", url: url, sha256: sha256.lowercased())
        addCustom(model); download(model)
    }
    func importModelRepository(_ address: String, engine: String, version: String) {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = value.replacingOccurrences(of: "https://huggingface.co/", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = raw.split(separator: "/")
        guard parts.count >= 2, (parts.count == 2 || parts[2] == "resolve" || parts[2] == "blob"), parts.prefix(2).allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }) else { message = "Enter a Hugging Face owner/repository or file URL."; return }
        let repo = parts.prefix(2).joined(separator: "/")
        Task {
            do {
                guard let api = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true") else { throw SpeechError.model("Invalid repository") }
                let (data, response) = try await URLSession.shared.data(from: api)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let revision = json["sha"] as? String, let siblings = json["siblings"] as? [[String: Any]] else { throw SpeechError.model("Cannot read repository metadata") }
                let names: [String]
                if engine == "sherpa" { names = try SherpaModelFiles.requiredFiles(version) }
                else {
                    let prefixes: [String] = engine == "canary" ? ["EncoderInt4.mlmodelc/", "DecoderInt4.mlmodelc/", "Projection.mlmodelc/", "Preprocessor.mlmodelc/"] : ["Encoder.mlmodelc/", "Decoder.mlmodelc/", "Decoderv2.mlmodelc/", "JointDecision.mlmodelc/", "JointDecisionv3.mlmodelc/", "Jointerv2.mlmodelc/", "Preprocessor.mlmodelc/"]
                    names = siblings.compactMap { $0["rfilename"] as? String }.filter { name in prefixes.contains(where: { name.hasPrefix($0) }) || ["vocab.json", "parakeet_vocab.json", "parakeet_v3_vocab.json", "config.json", "metadata.json"].contains(name) }
                    guard !names.isEmpty else { throw SpeechError.model("Repository does not contain compatible Core ML files") }
                }
                var files: [ModelFile] = []
                for name in names {
                    guard let entry = siblings.first(where: { $0["rfilename"] as? String == name }), let size = (entry["size"] as? NSNumber)?.int64Value, name.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) } }), let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(name)") else { throw SpeechError.model("Repository is missing \(name)") }
                    var checksum = (entry["lfs"] as? [String: Any])?["sha256"] as? String
                    if checksum == nil {
                        guard size <= 2_000_000 else { throw SpeechError.model("Repository is missing a checksum for \(name)") }
                        let (contents, reply) = try await URLSession.shared.data(from: url)
                        guard let response = reply as? HTTPURLResponse, (200..<300).contains(response.statusCode), Int64(contents.count) == size else { throw SpeechError.model("Cannot read \(name)") }
                        checksum = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
                    }
                    guard let checksum else { throw SpeechError.model("Missing checksum") }
                    files.append(ModelFile(path: name, url: url, size: size, sha256: checksum))
                }
                var model = Model(id: "custom-" + UUID().uuidString, name: repo, engine: engine, version: version)
                model.files = files; model.size = files.reduce(0) { $0 + $1.size }; addCustom(model); download(model)
            } catch { message = error.localizedDescription }
        }
    }
    func importModelManifest(_ address: String, engine: String, version: String) {
        guard let manifestURL = URL(string: address), ["https", "http"].contains(manifestURL.scheme?.lowercased() ?? "") else { message = "Enter an HTTP(S) manifest URL."; return }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: manifestURL)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 2_000_000 else { throw SpeechError.model("Cannot read model manifest") }
                let files = try JSONDecoder().decode([ModelFile].self, from: data)
                guard !files.isEmpty, files.count <= 10_000, files.allSatisfy({ file in file.size > 0 && file.size <= 20_000_000_000 && !file.path.isEmpty && file.sha256.count == 64 && file.sha256.allSatisfy(\.isHexDigit) && ["https", "http"].contains(file.url.scheme?.lowercased() ?? "") && !file.path.hasPrefix("/") && file.path.split(separator: "/").allSatisfy { $0 != "." && $0 != ".." } }) else { throw SpeechError.model("Model manifest has invalid files") }
                if engine == "sherpa" { let names = try Set(SherpaModelFiles.requiredFiles(version)); guard names.isSubset(of: Set(files.map(\.path))) else { throw SpeechError.model("Manifest is missing model files") } }
                var model = Model(id: "custom-" + UUID().uuidString, name: manifestURL.lastPathComponent, engine: engine, version: version)
                model.files = files; model.size = files.reduce(0) { $0 + $1.size }; addCustom(model); download(model)
            } catch { message = error.localizedDescription }
        }
    }
    func addCloudModel(provider: CloudProvider, name: String, address: String, key: String, fallbackID: String?) throws {
        let modelName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty, provider == .compatible || provider.models.contains(modelName) else { throw SpeechError.model("Choose a supported model.") }
        let endpoint: URL?
        if provider == .compatible {
            guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw SpeechError.model("Enter a valid HTTPS base URL.") }
            endpoint = url
        } else { endpoint = nil }
        let id = "custom-" + UUID().uuidString
        try CloudKeychain.save(key, id: id)
        var model = Model(id: id, name: "\(provider.title) · \(modelName)", engine: "cloud")
        model.cloudProvider = provider; model.cloudModel = modelName; model.cloudEndpoint = endpoint; model.fallbackID = fallbackID
        addCustom(model)
    }
    private func addCustom(_ model: Model) {
        models.append(model)
        let custom = models.filter { $0.id.hasPrefix("custom-") }
        if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: "customModels") }
    }
    func deleteModel(_ model: Model) {
        do {
            if ModelStore.exists(model) { try ModelStore.delete(model) }
            if model.id.hasPrefix("custom-") { models.removeAll { $0.id == model.id }; let custom = models.filter { $0.id.hasPrefix("custom-") }; UserDefaults.standard.set(try JSONEncoder().encode(custom), forKey: "customModels") }
            if UserDefaults.standard.string(forKey: "selectedModel") == model.id { UserDefaults.standard.set("whisper-tiny.en", forKey: "selectedModel"); unloadEngine() }
            if warmingID == model.id { warming?.cancel(); warming = nil; warmingID = ""; warmingToken = UUID() }
            objectWillChange.send()
        } catch { message = error.localizedDescription }

    }
    func cancelDownload() { downloadTask?.cancel() }
    func prepareToQuit() async { unloadEngine(); let task = downloadTask; task?.cancel(); await task?.value }
    func download(_ model: Model) {
        guard busyModel == nil else { return }
        busyModel = model.id; downloadProgress = 0
        downloadTask = Task {
            do { try await ModelStore.download(model) { [weak self] value in Task { @MainActor in self?.downloadProgress = value } } }
            catch is CancellationError { message = "Download canceled. You can resume it." }
            catch { message = error.localizedDescription }
            busyModel = nil; downloadTask = nil; objectWillChange.send()
        }
    }

}
struct HistoryEntry: Codable, Identifiable { var id = UUID(); let text: String; let date: Date }
