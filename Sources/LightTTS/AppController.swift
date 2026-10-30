import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import LightTTSCore
import ServiceManagement

@MainActor final class AppController: NSObject, ObservableObject {
    @Published var state = "idle"
    @Published var settingsSelection = "Sound"
    private var previousSettingsSelection = "Sound"
    @Published var level: Float = 0
    @Published var started = Date()
    @Published var message = ""
    @Published var history: [HistoryEntry] = []
    @Published var historySearch = ""
    @Published var historySearchVisible = false
    @Published var selectedHistory: HistoryEntry?
    @Published var hoveredHistoryID: UUID?
    @Published var showAdvanced = false
    @Published var playingHistoryID: UUID?
    @Published var historySegmented = false
    private var segmentStop: DispatchWorkItem?
    private var historyPlayer: AVAudioPlayer?
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var models: [Model] = []
    @Published var busyModel: String?
    @Published var downloadProgress: Double = 0
    var onCatalogReady: (() -> Void)?
    private var downloadTask: Task<Void, Never>?
    private var engine: (any TranscriptionEngine)?
    private var loadedID = ""
    private var warmingID = ""
    private var warmingToken = UUID()
    private var warming: Task<any TranscriptionEngine, Error>?
    private var audio: AudioCapture?
    private let audioSettings = AudioSettings()
    private let isTestAudio = !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty
    private var panel: NSPanel?
    private let hotkey = HotkeyMonitor()
    private var processing: Task<Void, Never>?
    private var focus: FocusTarget?
    private var sessionAutoPaste = true
    private var testAudio: [Float]?
    private var defaultsObserver: NSObjectProtocol?
    private var pressed = false
    private var pushHeld = false
    private var pushOwnsRecording = false
    private var mouseStart: Date?
    private var mouseOwnsRecording = false
    private var generation = 0
    private let historyURL = (CommandLine.arguments.contains("--ui-fixture") || !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty) ? FileManager.default.temporaryDirectory.appendingPathComponent("LightTTS-Fixture", isDirectory: true).appendingPathComponent("history.json") : ModelStore.directory.deletingLastPathComponent().appendingPathComponent("history.json")
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
            self.models = data.0
            if CommandLine.arguments.contains("--ui-fixture") {
                var sample = HistoryEntry(text: "A short sample transcription for the settings preview.", date: Date())
                sample.inputName = "Sample microphone"; sample.modelName = "Whisper Tiny"; sample.recordingDuration = 2.7; sample.processingDuration = 0.4; sample.mode = "Voice to text"
                if CommandLine.arguments.contains("--history-detail"), let source = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"], !source.isEmpty {
                    let directory = historyURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true), name = sample.id.uuidString + ".wav"
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    if (try? FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: directory.appendingPathComponent(name))) != nil { sample.audioFile = name; if let samples = try? AudioFileReader.read(URL(fileURLWithPath: source)) { sample.segments = AudioProcessing.speechSegments(samples); sample.waveform = AudioProcessing.waveform(samples) } }
                }
                self.history = [sample, HistoryEntry(text: "Another example recording, shown here with enough text to wrap onto a second line.", date: Date()), HistoryEntry(text: "An earlier example transcription.", date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)]
            } else { self.history = data.1; self.pruneHistory() }
            if CommandLine.arguments.contains("--history-detail") { self.selectedHistory = self.history.first }
            LaunchTrace.mark("catalog-ready"); self.onCatalogReady?()
        }
        if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { showPanel() }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == "idle", ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_STATE"] == nil else { return }
                if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { self.showPanel() } else { self.panel?.orderOut(nil) }
            }
        }
        if UserDefaults.standard.bool(forKey: "autoCheckUpdates") && !isTestAudio && !CommandLine.arguments.contains("--ui-fixture") { checkUpdates(interactive: false) }
        if let index = CommandLine.arguments.firstIndex(of: "--settings-page"), CommandLine.arguments.indices.contains(index + 1) { settingsSelection = CommandLine.arguments[index + 1] }
        if isTestAudio { DistributedNotificationCenter.default().addObserver(self, selector: #selector(testAudioToggle(_:)), name: Notification.Name("com.lighttts.test.toggle.\(Bundle.main.bundleIdentifier ?? "app")"), object: nil) }
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testToggle(_:)), name: Notification.Name("com.lighttts.test.toggle.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testHIDShortcut(_:)), name: Notification.Name("com.lighttts.test.hid.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        #endif
    }
    @objc private func testAudioToggle(_ notification: Notification) { if state == "recording" { stop() } else if state == "idle" { start() } }
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
    func selectSettings(_ selection: String) {
        if selection == "Library" && settingsSelection != "Library" { previousSettingsSelection = settingsSelection }
        if selection != "Library" { stopHistoryPlayback(); selectedHistory = nil; historySearchVisible = false; historySearch = "" }
        settingsSelection = selection
    }
    func leaveLibrary() { historySearchVisible = false; historySearch = ""; selectSettings(previousSettingsSelection) }
    func warmSelected() {
        let selected = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_MODEL"] ?? UserDefaults.standard.string(forKey: "selectedModel") ?? "whisper-tiny.en"
        guard selected != loadedID, selected != warmingID, let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { return }
        warming?.cancel()
        warmingID = selected; warmingToken = UUID()
        let token = warmingToken
        let task = Task.detached(priority: .utility) { try await ModelStore.engine(for: model) }
        warming = task
        Task { [weak self] in
            do { _ = try await task.value }
            catch { guard let self, self.warmingToken == token else { return }; self.warming = nil; self.warmingID = "" }
        }
    }
    @discardableResult func installHotkey() -> Bool {
        guard !isTestAudio && !CommandLine.arguments.contains("--ui-fixture") else { return false }
        hotkey.onShortcut = { [weak self] down in self?.handleShortcut(down) }
        hotkey.onPush = { [weak self] down in self?.handlePush(down) }
        hotkey.onMouse = { [weak self] down in self?.handleMouse(down) }
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

        }
    }
    private func handlePush(_ down: Bool) {
        pushHeld = down
        if down { if state == "idle" { pushOwnsRecording = true; start() } }
        else if pushOwnsRecording { pushOwnsRecording = false; if state == "starting" { cancel() } else if state == "recording" { stop() } }
    }
    private func handleMouse(_ down: Bool) {
        if down {
            mouseStart = Date()
            if state == "idle" { mouseOwnsRecording = true; start() }
            else if state == "recording" { mouseOwnsRecording = false; stop() }
        } else if let startTime = mouseStart {
            mouseStart = nil
            if mouseOwnsRecording && Date().timeIntervalSince(startTime) >= 0.3 { mouseOwnsRecording = false; if state == "starting" { cancel() } else if state == "recording" { stop() } }
        }
    }
    func start() {
        guard state == "idle" else { return }
        generation += 1; let current = generation
        state = "starting"
        sessionAutoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        focus = nil
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil {
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
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? ProcessInfo.processInfo.environment["LIGHTTTS_TEST_WAV"] {
                do { testAudio = try AudioFileReader.read(URL(fileURLWithPath: path)); started = Date(); state = "recording"; showPanel() } catch { fail(error.localizedDescription) }
                return
            }
            let allowed: Bool
            if isTestAudio { allowed = true } else { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
            guard current == generation, state == "starting" else { return }
            guard allowed else { fail("Microphone access is required. Enable it in System Settings."); return }
            do {
                let capture = AudioCapture { [weak self] value in Task { @MainActor in self?.level = value } }
                try capture.start(); audio = capture; if !isTestAudio || ProcessInfo.processInfo.environment["LIGHTTTS_TEST_VOLUME"] == "1" { message = audioSettings.begin() ?? "" }; AudioSettings.cue(start: true); started = Date(); state = "recording"; if isTestAudio { UserDefaults.standard.set("recording", forKey: "testRecordingState") }; showPanel()
            } catch { fail(error.localizedDescription) }
        }
    }
    func stop() {
        guard state == "recording" else { return }
        let rawSamples = testAudio ?? audio?.stop() ?? []
        let recordingDate = started, recordDuration = Double(rawSamples.count) / 16000
        let inputID = UserDefaults.standard.string(forKey: "inputDevice") ?? ""
        let inputName = inputID.isEmpty ? "System default" : (AVCaptureDevice.devices(for: .audio).first { $0.uniqueID == inputID }?.localizedName ?? "Microphone")
        let processingStart = Date()
        testAudio = nil; audio = nil; audioSettings.end(); AudioSettings.cue(start: false); state = "processing"; if isTestAudio { UserDefaults.standard.set("processing", forKey: "testRecordingState") }; let current = generation
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
                        else { resolved = try await ModelStore.engine(for: model) }
                    } catch { if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }; throw error }
                    if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }
                    try Task.checkCancellation(); guard current == generation else { return }
                    engine = resolved; loadedID = selected
                }
                guard let engine else { return }
                try Task.checkCancellation(); guard current == generation else { return }
                let remove = UserDefaults.standard.bool(forKey: "removeSilence"), normalize = UserDefaults.standard.bool(forKey: "normalizeAudio")
                let samples = await Task.detached(priority: .userInitiated) { AudioProcessing.apply(rawSamples, removeSilence: remove, normalize: normalize) }.value
                let text = try await engine.transcribe(samples: samples)
                guard current == generation else { return }
                guard !text.isEmpty else { throw SpeechError.audio("No speech detected.") }
                if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil {
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
                var item = HistoryEntry(text: text, date: recordingDate)
                item.inputName = inputName; item.recordingDuration = recordDuration; item.modelName = model.name; item.processingDuration = Date().timeIntervalSince(processingStart); item.mode = "Voice to text"
                if !isTestAudio {
                    let analysis = await Task.detached(priority: .utility) { (AudioProcessing.speechSegments(rawSamples), AudioProcessing.waveform(rawSamples)) }.value
                    item.segments = analysis.0; item.waveform = analysis.1
                    let directory = self.historyURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
                    let filename = item.id.uuidString + ".wav"
                    let written = await Task.detached(priority: .utility) { Self.writeRecording(rawSamples, to: directory.appendingPathComponent(filename)) }.value
                    if written { item.audioFile = filename }
                    if Task.isCancelled || current != generation { if written { try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename)) }; return }
                }
                history.insert(item, at: 0); if history.count > 500 { for old in history.dropFirst(500) { if let url = historyAudioURL(old) { try? FileManager.default.removeItem(at: url) } }; history.removeLast(history.count - 500) }; pruneHistory(); saveHistory(); state = "done"; if isTestAudio { UserDefaults.standard.set("done", forKey: "testRecordingState") }
                try? await Task.sleep(nanoseconds: 1_000_000_000); if current == generation { hide() }
            } catch { if current == generation { fail(error.localizedDescription) } }
        }
    }
    func cancel() { audioSettings.end(); generation += 1; processing?.cancel(); processing = nil; _ = audio?.stop(); audio = nil; testAudio = nil; hide() }
    private func hide() {
        state = "idle"; level = 0
        if UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") { showPanel() }
        else if let panel {
            let current = generation
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; panel.animator().alphaValue = 0 } completionHandler: { [weak self, weak panel] in
                Task { @MainActor in
                    guard let self, self.generation == current, self.state == "idle", !UserDefaults.standard.bool(forKey: "alwaysShowRecordingWindow") else { return }
                    panel?.orderOut(nil)
                }
            }
        }
    }
    func showPreviewState(_ previewState: String) { state = previewState; message = "Microphone access is required."; level = 0; showPanel() }
    private func fail(_ text: String) { message = text; state = "error"; showPanel() }
    private func showPanel() {
        if UserDefaults.standard.string(forKey: "recordingWindow") == "None", state != "error" { return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = NSWindow.Level(rawValue: 27); p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            p.contentView = NSHostingView(rootView: RecordingView(controller: self)); panel = p
        }
        if let frame = NSScreen.main?.visibleFrame, let p = panel { p.setFrameOrigin(NSPoint(x: frame.midX - p.frame.width / 2, y: frame.minY + 70));
            if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless(); NSAnimationContext.runAnimationGroup { context in context.duration = 0.15; p.animator().alphaValue = 1 } }
            else { p.alphaValue = 1 } }
    }
    func pruneHistory() { let days = UserDefaults.standard.integer(forKey: "historyRetentionDays"); if days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) { let removed = history.filter { $0.date < cutoff }; for item in removed { if let url = historyAudioURL(item) { try? FileManager.default.removeItem(at: url) } }; history.removeAll { $0.date < cutoff }; if !removed.isEmpty { saveHistory() } } }
    func checkUpdates(interactive: Bool = true) {
        guard let url = URL(string: "https://api.github.com/repos/imraghavojha/lighttts/releases/latest") else { return }
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["tag_name"] as? String else { throw URLError(.badServerResponse) }
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
                let newer = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).compare(current, options: .numeric) == .orderedDescending
                if interactive || newer { let alert = NSAlert(); alert.messageText = newer ? "Update available: \(version)" : "LightTTS is up to date"; alert.informativeText = newer ? "Visit the releases page to download the update." : "You have the latest release."; alert.addButton(withTitle: newer ? "Open Releases" : "OK"); if newer { alert.addButton(withTitle: "Later") }; if alert.runModal() == .alertFirstButtonReturn && newer { NSWorkspace.shared.open(URL(string: "https://github.com/imraghavojha/lighttts/releases/latest")!) } }
            } catch { if interactive { let alert = NSAlert(); alert.messageText = "Couldn't check for updates"; alert.informativeText = error.localizedDescription; alert.runModal() } }
        }
    }
    nonisolated private static func writeRecording(_ samples: [Float], to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let data = buffer.floatChannelData?[0] else { return false }
            buffer.frameLength = AVAudioFrameCount(samples.count); samples.withUnsafeBufferPointer { if let base = $0.baseAddress { data.update(from: base, count: samples.count) } }
            let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer); return true
        } catch { return false }
    }
    func historyAudioURL(_ item: HistoryEntry) -> URL? {
        guard let file = item.audioFile, file == item.id.uuidString + ".wav" else { return nil }
        let url = historyURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true).appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    func stopHistoryPlayback() { segmentStop?.cancel(); segmentStop = nil; historyPlayer?.stop(); historyPlayer = nil; playingHistoryID = nil }
    func toggleHistoryPlayback(_ item: HistoryEntry, segment: RecordingSegment? = nil) {
        segmentStop?.cancel(); segmentStop = nil
        if playingHistoryID == item.id { historyPlayer?.stop(); playingHistoryID = nil; return }
        guard let url = historyAudioURL(item) else { return }
        do {
            historyPlayer = try AVAudioPlayer(contentsOf: url); historyPlayer?.delegate = self
            if let segment { historyPlayer?.currentTime = segment.start }
            historyPlayer?.play(); playingHistoryID = item.id
            if let segment { let work = DispatchWorkItem { [weak self] in self?.historyPlayer?.stop(); self?.playingHistoryID = nil }; segmentStop = work; DispatchQueue.main.asyncAfter(deadline: .now() + max(0, segment.end - segment.start), execute: work) }
        } catch { message = error.localizedDescription }
    }
    func revealHistory(_ item: HistoryEntry) { NSWorkspace.shared.activateFileViewerSelecting([historyAudioURL(item) ?? historyURL]) }
    func deleteHistory(_ id: UUID) { if playingHistoryID == id { stopHistoryPlayback() }; if let item = history.first(where: { $0.id == id }), let url = historyAudioURL(item) { try? FileManager.default.removeItem(at: url) }; history.removeAll { $0.id == id }; saveHistory() }
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
            if UserDefaults.standard.string(forKey: "selectedModel") == model.id { UserDefaults.standard.set("whisper-tiny.en", forKey: "selectedModel"); engine = nil; loadedID = "" }
            if warmingID == model.id { warming?.cancel(); warming = nil; warmingID = ""; warmingToken = UUID() }
            objectWillChange.send()
        } catch { message = error.localizedDescription }
    }
    func cancelDownload() { downloadTask?.cancel() }
    func prepareToQuit() async { if state != "idle" { cancel() }; await audioSettings.waitForRestoration(); let task = downloadTask; task?.cancel(); await task?.value }
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
struct HistoryEntry: Codable, Identifiable { var id = UUID(); let text: String; let date: Date; var audioFile: String? = nil; var inputName: String? = nil; var modelName: String? = nil; var recordingDuration: Double? = nil; var processingDuration: Double? = nil; var mode: String? = nil; var segments: [RecordingSegment]? = nil; var waveform: [Float]? = nil }

extension AppController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.playingHistoryID = nil } }
}
