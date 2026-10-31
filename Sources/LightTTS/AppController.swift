import LightTTSRuntime
import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import CryptoKit
import LightTTSCore

import ServiceManagement

import Darwin
import IOKit.ps


@MainActor final class RecordingLevel: ObservableObject { @Published var value: Float = 0 }
@MainActor final class ModelProgress: ObservableObject { @Published var value: Double = 0 }

@MainActor final class AppController: NSObject, ObservableObject {
    @Published var state = "idle" { didSet { hotkey.setRecording(CancelRegistrationState.isActiveSession(state)) } }
    @Published var settingsSelection = "Sound"
    private var previousSettingsSelection = "Sound"
    let recordingLevel = RecordingLevel()
    @Published var started = Date()
    @Published var message = ""
    @Published var copiedToClipboard = false
    @Published var history: [HistoryEntry] = []
    @Published var historyWarning: String?
    @Published var historySearch = ""
    @Published var historySearchVisible = false
    @Published var selectedHistory: HistoryEntry?
        @Published var showAdvanced = false
    @Published var playingHistoryID: UUID?
    @Published var historySegmented = false
    @Published var reprocessingHistoryID: UUID?
    @Published var historyProcessingError: (id: UUID, message: String)?
    private var segmentStop: DispatchWorkItem?
    private var historyPlayer: AVAudioPlayer?
    @Published var loginEnabled = false
    @Published var models: [Model] = []
    @Published var busyModel: String?
    @Published var modelOperation: String?
    let modelProgress = ModelProgress()
    var onCatalogReady: (() -> Void)?
    private var downloadTask: Task<Void, Never>?
    private var engine: (any TranscriptionEngine)?
    private var unloadTimer: Timer?
    private var loadedID = ""
    private var warmingID = ""
    private var warmingToken = UUID()
    private var warming: Task<any TranscriptionEngine, Error>?

    private let captureService = CaptureService(factory: NativeCaptureDriverFactory())
    private let audioDucking = AudioDuckingService(driver: NativeAudioDuckingDriver())
    private let insertionService = makeNativeInsertionService()
    private let isTestAudio = !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty

    private var panel: NSPanel?
    private var panelDeadline: Task<Void, Never>?
    var recordingPanelVisible: Bool { panel?.isVisible ?? false }
    var recordingPanelTransparent: Bool { panel?.isOpaque == false && panel?.contentView?.layer?.isOpaque == false }
    private let hotkey = HotkeyMonitor()
    private var processing: Task<Void, Never>?
    private var sessionAutoPaste = true
    private var testAudio: [Float]?
    private var defaultsObserver: NSObjectProtocol?
    private var powerSource: CFRunLoopSource?
    private var pushHeld = false
    private var pushOwnsRecording = false
    private var recordingUsesPushToTalk = false
    private var mouseStart: Date?
    private var mouseOwnsRecording = false
    private var generation = 0
    @Published var historyMigration: Progress?
    private let historyQueue = DispatchQueue(label: "com.lighttts.history", qos: .utility)
    private let historyPersistence = HistoryPersistence()
    private var pendingHistoryAudio: [String: Data] = [:]
    var historyURL: URL {
        let fixture = CommandLine.arguments.contains("--ui-fixture") || !(ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? "").isEmpty
        let configured = UserDefaults.standard.string(forKey: "historyFolder")
        let folder = fixture ? FileManager.default.temporaryDirectory.appendingPathComponent("LightTTS-Fixture", isDirectory: true) : configured.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? ModelStore.directory.deletingLastPathComponent()
        return folder.appendingPathComponent("history.json")
    }
    func changeHistoryFolder(_ destination: URL) throws {
        let source = historyURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard source != destination else { return }
        guard historyMigration == nil, state == "idle" || state == "error" else { throw NSError(domain: "LightTTS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Wait for the current recording or folder change to finish."]) }
        guard !destination.path.hasPrefix(source.appendingPathComponent("Recordings", isDirectory: true).path + "/") else { throw NSError(domain: "LightTTS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Choose a folder outside the current Recordings folder."]) }
        stopHistoryPlayback()
        let progress = Progress(totalUnitCount: 0)
        progress.isCancellable = true
        historyMigration = progress
        historyQueue.async { [weak self] in
            let fm = FileManager.default
            let names = ["history.json", "Recordings"]
            var created: [URL] = []
            let result: Result<Void, Error> = Result {
                for name in names where fm.fileExists(atPath: destination.appendingPathComponent(name).path) {
                    throw NSError(domain: "LightTTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected folder already contains \(name). Choose an empty folder."])
                }
                do {
                    var items: [(URL, URL, Bool)] = []
                    for name in names {
                        let from = source.appendingPathComponent(name), to = destination.appendingPathComponent(name)
                        var directory: ObjCBool = false
                        guard fm.fileExists(atPath: from.path, isDirectory: &directory) else { continue }
                        items.append((from, to, directory.boolValue))
                        var enumerationError: Error?
                        if directory.boolValue, let enumerator = fm.enumerator(at: from, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: { _, error in enumerationError = error; return false }) {
                            var pathComponents: [String] = []
                            for case let url as URL in enumerator {
                                pathComponents = Array(pathComponents.prefix(max(0, enumerator.level - 1)))
                                pathComponents.append(url.lastPathComponent)
                                let relative = pathComponents.joined(separator: "/")
                                let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                                items.append((url, to.appendingPathComponent(relative), isDirectory))
                            }
                            if let error = enumerationError { throw error }
                        } else if directory.boolValue { throw CocoaError(.fileReadUnknown) }
                    }
                    progress.totalUnitCount = Int64(max(items.count, 1))
                    for (from, to, directory) in items {
                        if progress.isCancelled { throw CancellationError() }
                        if to.deletingLastPathComponent() == destination { created.append(to) }
                        if directory { try fm.createDirectory(at: to, withIntermediateDirectories: false) }
                        else { try fm.copyItem(at: from, to: to) }
                        progress.completedUnitCount += 1
                    }
                    if progress.isCancelled { throw CancellationError() }
                } catch { for url in created { try? fm.removeItem(at: url) }; throw error }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success: UserDefaults.standard.set(destination.path, forKey: "historyFolder"); self.saveHistory()
                case .failure(let error): if !(error is CancellationError) { self.message = "Could not change folder: " + error.localizedDescription }
                }
                self.historyMigration = nil
                self.pruneHistory()
            }
        }
    }
    func refreshModelIdleTimeout() { if state == "idle" || state == "error" { scheduleEngineUnload() } }
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
            if self.onACPower && !CommandLine.arguments.contains("--ui-fixture") { self.warmSelected() }

            await ModelStore.refreshAppleStatus(); self.objectWillChange.send()

        }
        if UserDefaults.standard.string(forKey: "recordingWindow") == "Classic" { UserDefaults.standard.set("Mini", forKey: "recordingWindow") }
        if UserDefaults.standard.string(forKey: "recordingSound") == "Muffle" { UserDefaults.standard.set("Lower", forKey: "recordingSound") }
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<AppController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in controller.powerChanged() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
        preparePanel()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == "idle", ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_STATE"] == nil else { return }
                if !self.onACPower && !self.keepModelLoaded && (self.engine != nil || self.warming != nil) { self.unloadEngine() }
                self.dismissPanel()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsChanged), name: .shortcutsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutCaptureChanged), name: .shortcutCaptureChanged, object: nil)
        if let index = CommandLine.arguments.firstIndex(of: "--settings-page"), CommandLine.arguments.indices.contains(index + 1) { settingsSelection = CommandLine.arguments[index + 1] }
        if isTestAudio { DistributedNotificationCenter.default().addObserver(self, selector: #selector(testAudioToggle(_:)), name: Notification.Name("com.lighttts.test.toggle.\(Bundle.main.bundleIdentifier ?? "app")"), object: nil) }
        #if DEBUG
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testToggle(_:)), name: Notification.Name("com.lighttts.test.toggle.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(testHIDShortcut(_:)), name: Notification.Name("com.lighttts.test.hid.\(ProcessInfo.processInfo.processIdentifier)"), object: nil)
        #endif
    }
    @objc private func shortcutsChanged() { if !ShortcutButton.isRecording && !MouseShortcutButton.isRecording { installHotkey() } }
    @objc private func shortcutCaptureChanged() { if ShortcutButton.isRecording || MouseShortcutButton.isRecording { hotkey.stop() } else { installHotkey() } }
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
        let selected = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_MODEL"] ?? UserDefaults.standard.string(forKey: "selectedModel") ?? ModelDefaults.selectedModel
        guard selected != loadedID, selected != warmingID, let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { return }
        warming?.cancel()
        warmingID = selected; warmingToken = UUID()
        let token = warmingToken
        let onCrash: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.warmingToken == token else { return }
                if self.state == "idle" || self.state == "error" { self.unloadEngine() }
                else { self.fail("Speech engine exited unexpectedly. Try recording again.") }
            }
        }
        let languageID = model.fallbackID ?? model.id
        let language = UserDefaults.standard.string(forKey: "canaryLanguage." + languageID) ?? "en"
        let task = Task.detached(priority: .utility) { () -> any TranscriptionEngine in
            try await HelperEngine.load(model, language: language, onCrash: onCrash)
        }
        warming = task
        if state == "idle" || state == "error" { scheduleEngineUnload() }
        Task { [weak self] in
            do { let resolved = try await task.value
                guard let self, self.warmingToken == token else { (resolved as? HelperEngine)?.terminate(); return }
                self.engine = resolved; self.loadedID = selected; self.warming = nil; self.warmingID = ""
                if self.state == "idle" || self.state == "error" { self.scheduleEngineUnload() }
            }
            catch { guard let self, self.warmingToken == token else { return }; self.warming = nil; self.warmingID = ""; if !(error is CancellationError) && self.state != "idle" && self.state != "error" { self.fail(error.localizedDescription) } }
        }
    }
    func reloadSelectedModel() {
        unloadEngine()
        if onACPower { warmSelected() }
    }
    private var onACPower: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return source as String == kIOPSACPowerValue
    }
    private func powerChanged() {
        if onACPower { unloadTimer?.invalidate(); unloadTimer = nil; warmSelected() }
        else if state == "idle" || state == "error" { scheduleEngineUnload() }
    }
    @discardableResult func installHotkey() -> Bool {
        guard !isTestAudio && !CommandLine.arguments.contains("--ui-fixture") && !ShortcutButton.isRecording && !MouseShortcutButton.isRecording else { return false }
        hotkey.onShortcut = { [weak self] down in self?.handleShortcut(down) }
        hotkey.onPush = { [weak self] down in self?.handlePush(down) }
        hotkey.onMouse = { [weak self] down in self?.handleMouse(down) }
        hotkey.onEscape = { [weak self] in if self?.state != "idle" { self?.cancel() } }
        let installed = hotkey.install()
        if hotkey.registrationFailed { message = "A shortcut is unavailable. Choose another in Configuration → Keyboard Shortcuts." }
        else if message.contains("shortcut") || message.contains("Accessibility") { message = "" }
        return installed
    }
    func requestPermissions() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        installHotkey()
    }
    func handleShortcut(_ down: Bool) {
        if down { if state == "recording" { LaunchTrace.mark("hotkey-stop") }; toggleRecording() }
    }
    func toggleRecording() {
        if state == "error" { cancel() }
        if ["starting", "processing", "loading"].contains(state) { cancel() }
        else if state == "recording" { stop() }
        else if state == "idle" { start() }
    }
    private func handlePush(_ down: Bool) {
        pushHeld = down
        if down { if state == "error" { cancel() }; if state == "idle" { pushOwnsRecording = true; start(pushToTalk: true) } }
        else if pushOwnsRecording { if state == "recording" { LaunchTrace.mark("hotkey-stop") }; pushOwnsRecording = false; if state == "starting" { cancel() } else if state == "recording" { stop() } }
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
    func start(pushToTalk: Bool = false) {
        guard state == "idle", historyMigration == nil, reprocessingHistoryID == nil else { return }
        copiedToClipboard = false
        recordingUsesPushToTalk = pushToTalk
        unloadTimer?.invalidate(); unloadTimer = nil
        generation += 1; let current = generation
        LaunchTrace.mark("recording-start-request")
        state = "starting"
        armPanelDeadline(seconds: 30, generation: current, message: "Recording could not start in time. Try again.")
        showPanel()
        warmSelected()
        sessionAutoPaste = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_PASTE"] != "1" {
            do {
                try startCapture()
                started = Date()
                state = "recording"
                showPanel()
            } catch { fail(error.localizedDescription) }
            return
        }
        Task {
            if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil {
                do {
                    try startCapture()
                    started = Date()
                    state = "recording"
                    showPanel()
                } catch { fail(error.localizedDescription) }
                return
            }
            #if DEBUG
            if let path = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] ?? ProcessInfo.processInfo.environment["LIGHTTTS_TEST_WAV"] {
                do { testAudio = try AudioFileReader.read(URL(fileURLWithPath: path)); started = Date(); state = "recording"; showPanel() } catch { fail(error.localizedDescription) }
                return
            }
            #endif
            let allowed: Bool
            if isTestAudio { allowed = true } else { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
            guard current == generation, state == "starting" else { return }
            guard allowed else { fail("Microphone access is required. Enable it in System Settings."); return }
            do {
                let manageAudio = !isTestAudio || ProcessInfo.processInfo.environment["LIGHTTTS_TEST_VOLUME"] == "1"
                try startCapture()
                LaunchTrace.mark("capture-started")
                panelDeadline?.cancel()
                started = Date()
                state = "recording"
                if isTestAudio { UserDefaults.standard.set("recording", forKey: "testRecordingState") }
                showPanel()
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == current, self.state == "recording" else { return }
                    if manageAudio {
                        self.audioDucking.begin(session: SessionID(generation: UInt64(current)), options: self.duckingOptions()) { [weak self] warning in
                            guard let self, self.generation == current, self.state == "recording" else { return }
                            self.message = warning ?? ""
                        }
                    }
                    AudioSettings.cue(start: true)
                }
            } catch { fail(error.localizedDescription) }
        }
    }
    private func startCapture() throws {
        let deviceUID = UserDefaults.standard.string(forKey: "inputDeviceUID") ?? ""
        try captureService.start(deviceUID: deviceUID) { [weak self] value in
            self?.recordingLevel.value = value
        }
    }

    private func duckingOptions() -> DuckingOptions {
        let defaults = UserDefaults.standard
        let mode: DuckingOptions.Mode
        switch defaults.string(forKey: "recordingSound") ?? "Pause" {
        case "Pause": mode = .pause
        case "Mute": mode = .mute
        case "Lower": mode = .lower
        default: mode = .none
        }
        return DuckingOptions(
            mode: mode,
            increaseMicrophoneVolume: defaults.bool(forKey: "increaseMicVolume")
        )
    }

    private func endDucking() {
        audioDucking.end(session: SessionID(generation: UInt64(generation)))
    }

    func stop() {
        guard state == "recording" else { return }
        LaunchTrace.mark("stop-enter")

        let stopFocus = insertionService.captureAtStop()
        LaunchTrace.mark("recording-stopped")
        let finishedCapture = captureService.stop()
        let rawSamples = testAudio ?? finishedCapture?.pcm.samples ?? []
        LaunchTrace.mark("capture-stopped")
        let elapsed = Date().timeIntervalSince(started)
        let recordingDate = started, recordDuration = Double(rawSamples.count) / 16000
        let inputID = UserDefaults.standard.string(forKey: "inputDeviceUID") ?? ""
        let inputName = inputID.isEmpty ? "System default" : (AVCaptureDevice.devices(for: .audio).first { $0.uniqueID == inputID }?.localizedName ?? "Microphone")
        let processingStart = Date()
        // AVAudioEngine teardown can block the main thread; retain the stopped capture
        // until after text insertion instead of releasing it on the stop path.
        LaunchTrace.mark("stop-setup-start")
        testAudio = nil
        endDucking()
        AudioSettings.cue(start: false)
        state = "processing"
        runPendingHistoryReprocess()
        if isTestAudio { UserDefaults.standard.set("processing", forKey: "testRecordingState") }
        let current = generation
        LaunchTrace.mark("stop-setup-end")
        armPanelDeadline(seconds: 330, generation: current, message: "Transcription timed out. Try recording again.")
        let usedPushToTalk = recordingUsesPushToTalk
        recordingUsesPushToTalk = false
        if let error = AudioProcessing.recordingError(samples: rawSamples, duration: elapsed, pushToTalk: usedPushToTalk) { fail(error); return }

        LaunchTrace.mark("processing-task-enqueued")
        processing = Task { [finishedCapture] in
            defer { withExtendedLifetime(finishedCapture) {} }
            LaunchTrace.mark("processing-task-start")
            do {
                let selected = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_MODEL"] ?? UserDefaults.standard.string(forKey: "selectedModel") ?? ModelDefaults.selectedModel
                LaunchTrace.mark("model-check-start")
                guard let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { throw SpeechError.model("Download a model in Models settings first.") }
                LaunchTrace.mark("model-check-end")
                if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE model selected=%@ loaded=%@ engine=%@", selected, loadedID, engine == nil ? "nil" : "ready") }
                if loadedID != selected || engine == nil {
                    state = "loading"
                    warmSelected()
                    let token = warmingToken
                    let resolved: any TranscriptionEngine
                    do {
                        if warmingID == selected, let warming { resolved = try await warming.value }
                        else { let language = UserDefaults.standard.string(forKey: "canaryLanguage." + (model.fallbackID ?? model.id)) ?? "en"; resolved = try await HelperEngine.load(model, language: language) }
                    } catch { if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }; throw error }
                    if warmingID == selected && warmingToken == token { warmingID = ""; warming = nil }
                    try Task.checkCancellation(); guard current == generation else { return }
                    engine = resolved; loadedID = selected
                }
                state = "processing"
                guard let engine else { return }
                try Task.checkCancellation(); guard current == generation else { return }

                let remove = UserDefaults.standard.bool(forKey: "removeSilence"), normalize = UserDefaults.standard.bool(forKey: "normalizeAudio")
                LaunchTrace.mark("audio-processing-start")
                let samples = await Task.detached(priority: .userInitiated) { AudioProcessing.apply(rawSamples, removeSilence: remove, normalize: normalize) }.value
                LaunchTrace.mark("audio-processing-end")
                guard !samples.isEmpty else { throw SpeechError.audio("No speech detected. Try speaking louder or turn off silence removal.") }
                LaunchTrace.mark("inference-start")
                let text = try await engine.transcribe(samples: samples)
                LaunchTrace.mark("inference-finished")

                guard current == generation else { return }
                if !keepModelLoaded && !onACPower { unloadEngine() }
                guard !text.isEmpty else { throw SpeechError.audio("No speech detected.") }
                if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_PASTE"] != "1" {
                    print("LIGHTTTS_TEST transcription completed, samples: \(samples.count)")
                    state = "done"
                    try? await Task.sleep(nanoseconds: 150_000_000); if current == generation { hide() }
                    return
                }
                LaunchTrace.mark("paste-start")
                let outcome = await insertionService.deliver(text, to: stopFocus, autoPaste: sessionAutoPaste) {
                    current == self.generation && self.processing?.isCancelled != true
                }
                LaunchTrace.mark("paste-end")
                try Task.checkCancellation(); guard current == generation, outcome.delivery != .skipped else { return }
                let pasteWarning = outcome.warning
                let copied = outcome.delivery == .copied

                hideImmediately()
                LaunchTrace.mark("text-inserted")
                var item = HistoryEntry(text: text, date: recordingDate)
                item.inputName = inputName; item.recordingDuration = recordDuration; item.modelName = model.name; item.processingDuration = Date().timeIntervalSince(processingStart); item.mode = "Voice to text"
                if !isTestAudio {
                    let analysis = await Task.detached(priority: .utility) { (AudioProcessing.speechSegments(rawSamples), AudioProcessing.waveform(rawSamples)) }.value
                    item.segments = analysis.0; item.waveform = analysis.1
                    let filename = item.id.uuidString + ".wav"
                    let recording = await Task.detached(priority: .utility) { Self.recordingData(rawSamples) }.value
                    guard !Task.isCancelled, current == generation else { return }
                    item.audioFile = filename; pendingHistoryAudio[filename] = recording
                }
                panelDeadline?.cancel()
                history.insert(item, at: 0); if history.count > 500 { deleteRecordings(Array(history.dropFirst(500))); history.removeLast(history.count - 500) }; pruneHistory(); saveHistory(); if let pasteWarning { fail(pasteWarning); return }; copiedToClipboard = copied; if UserDefaults.standard.bool(forKey: "closeAfterTranscription") { state = "idle"; scheduleEngineUnload() } else { state = "done" }; if isTestAudio { UserDefaults.standard.set("done", forKey: "testRecordingState") }

                if state == "done" { try? await Task.sleep(nanoseconds: 150_000_000); if current == generation { hide() } }
            } catch { if current == generation { fail(error.localizedDescription) } }
        }
    }

    func cancel() {
        panelDeadline?.cancel()
        message = ""
        endDucking()
        generation += 1
        processing?.cancel()
        processing = nil
        captureService.cancel()
        testAudio = nil
        recordingUsesPushToTalk = false
        unloadEngine()
        hide()
        runPendingHistoryReprocess()
    }

    private func hideImmediately() {
        recordingLevel.value = 0; panel?.orderOut(nil)
    }

    private func hide() {
        state = "idle"; recordingLevel.value = 0
        if onACPower { warmSelected() }
        scheduleEngineUnload()
        panel?.orderOut(nil)
    }
    func refreshRecordingWindow() { if state != "idle" { showPanel() } else { panel?.orderOut(nil) } }
    func showPreviewState(_ previewState: String) { state = previewState; message = "Microphone access is required."; recordingLevel.value = 0; showPanel() }
    private func dismissPanel() {
        panel?.orderOut(nil)
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
    // Set modelIdleTimeoutSeconds in defaults to change the five-minute default.
    private func scheduleEngineUnload() {
        unloadTimer?.invalidate(); unloadTimer = nil
        guard engine != nil || warming != nil else { return }
        if onACPower { return }
        guard keepModelLoaded else { unloadEngine(); return }
        let configured = UserDefaults.standard.object(forKey: "modelIdleTimeoutSeconds") == nil ? 300 : UserDefaults.standard.double(forKey: "modelIdleTimeoutSeconds")
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
        panelDeadline?.cancel()
        endDucking()
        generation += 1; processing?.cancel(); processing = nil
        captureService.cancel()
        testAudio = nil
        recordingUsesPushToTalk = false
        recordingLevel.value = 0
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS error: \(text)\n", stderr) }
        unloadEngine(); message = text; state = "error"; showPanel(); runPendingHistoryReprocess()
        let current = generation
        panelDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self, self.generation == current, self.state == "error" else { return }
            self.cancel()
        }
    }
    private func armPanelDeadline(seconds: UInt64, generation: Int, message: String) {
        panelDeadline?.cancel()
        panelDeadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.fail(message)
        }
    }
    private func preparePanel() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 160), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = NSWindow.Level(rawValue: 27); p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = false
            let host = NSHostingView(rootView: RecordingView(controller: self))
            host.wantsLayer = true; host.layer?.isOpaque = false; host.layer?.backgroundColor = NSColor.clear.cgColor
            p.contentView = host; panel = p
            p.contentView?.layoutSubtreeIfNeeded()
        }
    }
    private func showPanel() {
        guard state != "idle" else { panel?.orderOut(nil); return }
        if UserDefaults.standard.string(forKey: "recordingWindow") == "None", state != "error" { panel?.orderOut(nil); return }
        preparePanel()
        if let frame = NSScreen.main?.visibleFrame, let p = panel { p.setFrameOrigin(NSPoint(x: frame.midX - p.frame.width / 2, y: frame.minY + 70));
            if !p.isVisible { p.alphaValue = 1; p.orderFrontRegardless(); LaunchTrace.mark("panel-ordered-front") }
            else { p.alphaValue = 1 } }
    }

    func pruneHistory() { guard historyMigration == nil else { return }; let days = UserDefaults.standard.integer(forKey: "historyRetentionDays"); if days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) { let removed = history.filter { $0.date < cutoff }; deleteRecordings(removed); history.removeAll { $0.date < cutoff }; if !removed.isEmpty { saveHistory() } } }
    func refreshLoginStatus() { loginEnabled = SMAppService.mainApp.status == .enabled }
    func setLoginEnabled(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message = error.localizedDescription }
        refreshLoginStatus()
    }
    nonisolated private static func recordingData(_ samples: [Float]) -> Data {
        var result = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; withUnsafeBytes(of: &value) { result.append(contentsOf: $0) } }
        let size = UInt32(samples.count * MemoryLayout<Float>.size)
        result.append(contentsOf: "RIFF".utf8); append(size + 36); result.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(3)); append(UInt16(1)); append(UInt32(16000)); append(UInt32(64000)); append(UInt16(4)); append(UInt16(32))
        result.append(contentsOf: "data".utf8); append(size)
        for sample in samples { append(sample.bitPattern) }
        return result
    }
    func historyAudioURL(_ item: HistoryEntry) -> URL? {
        guard let file = item.audioFile, file == item.id.uuidString + ".wav" else { return nil }
        let url = historyURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true).appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    private var pendingHistoryReprocess: HistoryEntry?
    private func runPendingHistoryReprocess() {
        guard let item = pendingHistoryReprocess else { return }
        pendingHistoryReprocess = nil; reprocessingHistoryID = nil; processHistoryAgain(item)
    }
    func processHistoryAgain(_ item: HistoryEntry) {
        guard reprocessingHistoryID == nil, historyMigration == nil, let url = historyAudioURL(item) else { return }
        reprocessingHistoryID = item.id; historyProcessingError = nil
        if state == "starting" || state == "recording" { pendingHistoryReprocess = item; return }
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? ModelDefaults.selectedModel
        Task {
            do {
                guard let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { throw SpeechError.model("Download a model in Models settings first.") }
                let start = Date()
                let remove = UserDefaults.standard.bool(forKey: "removeSilence"), normalize = UserDefaults.standard.bool(forKey: "normalizeAudio")
                let samples = try await Task.detached(priority: .userInitiated) { AudioProcessing.apply(try AudioFileReader.read(url), removeSilence: remove, normalize: normalize) }.value
                let language = UserDefaults.standard.string(forKey: "canaryLanguage." + (model.fallbackID ?? model.id)) ?? "en"
                let worker = try await HelperEngine.load(model, language: language)
                defer { (worker as? HelperEngine)?.terminate() }
                let text = try await worker.transcribe(samples: samples)
                guard !text.isEmpty else { throw SpeechError.audio("No speech detected.") }
                if let index = history.firstIndex(where: { $0.id == item.id }) {
                    history[index].text = text; history[index].modelName = model.name; history[index].processingDuration = Date().timeIntervalSince(start)
                    if selectedHistory?.id == item.id { selectedHistory = history[index] }
                    saveHistory()
                }
            } catch { historyProcessingError = (item.id, error.localizedDescription) }
            reprocessingHistoryID = nil
        }
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
    func deleteHistory(_ id: UUID) { guard historyMigration == nil else { return }; if playingHistoryID == id { stopHistoryPlayback() }; if let item = history.first(where: { $0.id == id }) { deleteRecordings([item]) }; history.removeAll { $0.id == id }; saveHistory() }
    private func deleteRecordings(_ entries: [HistoryEntry]) {
        let directory = historyURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
        let names = entries.compactMap { item -> String? in
            guard let name = item.audioFile, name == item.id.uuidString + ".wav" else { return nil }
            return name
        }
        historyQueue.async { for name in names { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) } }
    }
    private func saveHistory() {
        let snapshot = history, url = historyURL, recordings = pendingHistoryAudio
        pendingHistoryAudio.removeAll()
        let fallback = ModelStore.directory.deletingLastPathComponent()
        let configured = UserDefaults.standard.string(forKey: "historyFolder") != nil && !CommandLine.arguments.contains("--ui-fixture") && !isTestAudio
        historyQueue.async { [weak self, historyPersistence] in
            for (name, data) in recordings { historyPersistence.enqueueRecording(data, named: name) }
            let result: (folder: URL, fellBack: Bool, error: Error?)
            do { result = historyPersistence.save(try JSONEncoder().encode(snapshot), in: url.deletingLastPathComponent(), fallback: configured ? fallback : nil) }
            catch { result = (url.deletingLastPathComponent(), false, error) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let changedFolder = result.fellBack && UserDefaults.standard.string(forKey: "historyFolder") == url.deletingLastPathComponent().path
                if changedFolder { UserDefaults.standard.removeObject(forKey: "historyFolder") }
                if let error = result.error {
                    let prefix = changedFolder ? "History folder unavailable; using Application Support. " : ""
                    self.historyWarning = prefix + "History could not be saved: \(error.localizedDescription). It will be retried on the next save."
                } else if changedFolder { self.historyWarning = "History folder unavailable. Using Application Support instead." }
                else if !result.fellBack && self.historyWarning?.contains("History could not be saved:") == true { self.historyWarning = nil }
            }
        }
    }
    func importLocalModel(engine: String = "whisper", version: String = "") {
        let panel = NSOpenPanel(); panel.canChooseDirectories = engine != "whisper"; panel.canChooseFiles = true; panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard busyModel == nil else { message = "Wait for the current model operation to finish."; return }
        let id = "custom-" + UUID().uuidString
        busyModel = id; modelOperation = "Importing model…"
        Task {
            do {
                let model = try await Task.detached(priority: .userInitiated) { () throws -> Model in
                    var model = Model(id: id, name: url.lastPathComponent, engine: engine, version: version.isEmpty ? nil : version)
                    if engine == "whisper" { try ModelStore.importFile(url, id: id) }
                    else {
                        let isDirectory = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                        let source = isDirectory && !url.lastPathComponent.hasSuffix(".mlmodelc") ? url : url.deletingLastPathComponent()
                        if engine == "sherpa" { model.files = try SherpaModelFiles.requiredFiles(version).map { ModelFile(path: $0, url: source.appendingPathComponent($0), size: 0, sha256: "") } }
                        try ModelStore.importDirectory(source, model: model)
                    }
                    return model
                }.value
                addCustom(model)
            } catch { message = error.localizedDescription }
            busyModel = nil; modelOperation = nil
        }
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
        guard busyModel == nil else { return }
        busyModel = model.id; modelOperation = "Deleting model…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { if ModelStore.exists(model) { try ModelStore.delete(model) } }.value
                if model.id.hasPrefix("custom-") { models.removeAll { $0.id == model.id }; let custom = models.filter { $0.id.hasPrefix("custom-") }; UserDefaults.standard.set(try JSONEncoder().encode(custom), forKey: "customModels") }
                if UserDefaults.standard.string(forKey: "selectedModel") == model.id { UserDefaults.standard.set(ModelDefaults.selectedModel, forKey: "selectedModel"); unloadEngine() }
                if warmingID == model.id { warming?.cancel(); warming = nil; warmingID = ""; warmingToken = UUID() }
            } catch { message = error.localizedDescription }
            busyModel = nil; modelOperation = nil; objectWillChange.send()
        }
    }
    func cancelDownload() { downloadTask?.cancel() }

    func beginQuit() {
        downloadTask?.cancel(); processing?.cancel(); warming?.cancel()
        pendingHistoryReprocess = nil
        endDucking()
        if state != "idle" { cancel() }
        unloadEngine()
    }
    func finishQuit() async {
        await audioDucking.waitForRestoration()
        await withCheckedContinuation { continuation in historyQueue.async { continuation.resume() } }
        await downloadTask?.value
    }

    func download(_ model: Model) {
        guard busyModel == nil else { return }
        busyModel = model.id; modelProgress.value = 0
        downloadTask = Task {
            do { try await ModelStore.download(model) { [weak self] value in Task { @MainActor in self?.modelProgress.value = value } } }
            catch is CancellationError { message = "Download canceled. You can resume it." }
            catch { message = error.localizedDescription }
            busyModel = nil; downloadTask = nil; objectWillChange.send()
        }
    }

}
struct HistoryEntry: Codable, Identifiable { var id = UUID(); var text: String; let date: Date; var audioFile: String? = nil; var inputName: String? = nil; var modelName: String? = nil; var recordingDuration: Double? = nil; var processingDuration: Double? = nil; var mode: String? = nil; var segments: [RecordingSegment]? = nil; var waveform: [Float]? = nil }

extension AppController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in self.playingHistoryID = nil } }
}
