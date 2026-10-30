import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
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
    private var audio: AudioCapture?
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
        let task = Task.detached(priority: .utility) { [weak self] () -> any TranscriptionEngine in
            try await HelperEngine.load(model) {
                Task { @MainActor [weak self] in
                    guard let self, self.warmingToken == token else { return }
                    self.processing?.cancel()
                    self.fail("Speech engine exited unexpectedly. Try recording again.")
                }
            }
        }
        warming = task
        if state == "idle" || state == "error" { scheduleEngineUnload() }
        Task { [weak self] in
            do { _ = try await task.value }
            catch { guard let self, self.warmingToken == token else { return }; self.warming = nil; self.warmingID = "" }
        }
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
    private func handleShortcut(_ down: Bool) {
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
    private func fail(_ text: String) { if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS error: \(text)\n", stderr) }; unloadEngine(); message = text; state = "error"; showPanel() }
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
    func importLocalModel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.data]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = "custom-" + UUID().uuidString
        do { try ModelStore.importFile(url, id: id); addCustom(Model(id: id, name: url.lastPathComponent, engine: "whisper")) }
        catch { message = error.localizedDescription }
    }
    func importRemoteModel(_ address: String, sha256: String) {
        guard let url = URL(string: address), url.scheme?.lowercased() == "https" else { message = "Enter a valid HTTPS model URL."; return }
        guard sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }) else { message = "Enter the model SHA-256."; return }
        let model = Model(id: "custom-" + UUID().uuidString, name: url.lastPathComponent, engine: "whisper", url: url, sha256: sha256.lowercased())
        addCustom(model); download(model)
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
