import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import LightTTSCore

@MainActor final class AppController: NSObject, ObservableObject {
    @Published var state = "idle"
    @Published var settingsSelection = "Sound"
    @Published var level: Float = 0
    @Published var started = Date()
    @Published var message = ""
    @Published var history: [HistoryEntry] = []
    @Published var models = (try? ModelCatalog.load()) ?? []
    @Published var busyModel: String?
    private var engine: (any TranscriptionEngine)?
    private var loadedID = ""
    private var warmingID = ""
    private var warming: Task<any TranscriptionEngine, Error>?
    private var audio: AudioCapture?
    private var panel: NSPanel?
    private var monitor: Any?
    private var localMonitor: Any?
    private var pressed = false
    private var generation = 0
    private let historyURL = ModelStore.directory.deletingLastPathComponent().appendingPathComponent("history.json")
    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "customModels"), let custom = try? JSONDecoder().decode([Model].self, from: data) { models.append(contentsOf: custom) }
        if let data = try? Data(contentsOf: historyURL), let items = try? JSONDecoder().decode([HistoryEntry].self, from: data) { history = items }
        installHotkey()
        warmSelected()
    }
    func warmSelected() {
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? "whisper-tiny.en"
        guard selected != loadedID, selected != warmingID, let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { return }
        warmingID = selected
        warming = Task.detached(priority: .utility) { try await ModelStore.engine(for: model) }
    }
    func installHotkey() {
        if let monitor { NSEvent.removeMonitor(monitor) }; if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in Task { @MainActor in self?.handle(event) } }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event); return event }
    }
    private func handle(_ event: NSEvent) {
        if event.type == .keyDown && event.keyCode == 53 && state != "idle" { cancel(); return }
        let rightOption = UserDefaults.standard.bool(forKey: "rightOption")
        let down: Bool
        if rightOption {
            guard event.type == .flagsChanged && event.keyCode == 61 else { return }
            down = event.modifierFlags.contains(.option)
        } else {
            let code = UserDefaults.standard.object(forKey: "hotkeyCode") as? Int ?? 49
            guard Int(event.keyCode) == code, event.type == .keyDown || event.type == .keyUp else { return }
            down = event.type == .keyDown && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            if event.isARepeat { return }
        }
        if down && !pressed { pressed = true; if UserDefaults.standard.bool(forKey: "pushToTalk") { start() } else if state == "recording" { stop() } else if state == "idle" { start() } }
        else if !down && pressed { pressed = false; if UserDefaults.standard.bool(forKey: "pushToTalk") && state == "recording" { stop() } }
    }
    func start() {
        guard state == "idle" else { return }
        generation += 1; let current = generation
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard current == generation else { return }
            guard allowed else { fail("Microphone access is required. Enable it in System Settings."); return }
            do {
                let capture = AudioCapture { [weak self] value in Task { @MainActor in self?.level = value } }
                try capture.start(); audio = capture; started = Date(); state = "recording"; showPanel()
            } catch { fail(error.localizedDescription) }
        }
    }
    func stop() {
        guard state == "recording", let audio else { return }
        let samples = audio.stop(); self.audio = nil; state = "processing"; let current = generation
        Task {
            do {
                let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? "whisper-tiny.en"
                guard let model = models.first(where: { $0.id == selected }), ModelStore.exists(model) else { throw SpeechError.model("Download a model in Models settings first.") }
                if loadedID != selected || engine == nil {
                    warmSelected()
                    if warmingID == selected, let warming { engine = try await warming.value }
                    else { engine = try await ModelStore.engine(for: model) }
                    loadedID = selected; warmingID = ""; warming = nil
                }
                guard let engine else { return }
                let text = try await engine.transcribe(samples: samples)
                guard current == generation else { return }
                guard !text.isEmpty else { throw SpeechError.audio("No speech detected.") }
                guard AXIsProcessTrusted() else { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary); throw SpeechError.audio("Allow Accessibility access in System Settings to paste text.") }
                paste(text); history.insert(HistoryEntry(text: text, date: Date()), at: 0); saveHistory(); state = "done"
                try? await Task.sleep(nanoseconds: 1_000_000_000); if current == generation { hide() }
            } catch { if current == generation { fail(error.localizedDescription) } }
        }
    }
    func cancel() { generation += 1; _ = audio?.stop(); audio = nil; hide() }
    private func hide() { panel?.orderOut(nil); state = "idle"; level = 0 }
    private func fail(_ text: String) { message = text; state = "error"; showPanel() }
    private func showPanel() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 64), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            p.isFloatingPanel = true; p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.backgroundColor = .clear; p.isOpaque = false; p.hasShadow = true
            p.contentView = NSHostingView(rootView: RecordingView(controller: self)); panel = p
        }
        if let frame = NSScreen.main?.visibleFrame, let p = panel { p.setFrameOrigin(NSPoint(x: frame.midX - p.frame.width / 2, y: frame.minY + 70)); p.orderFrontRegardless() }
    }
    private func paste(_ text: String) {
        let board = NSPasteboard.general
        let old = board.pasteboardItems?.map { item in item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } } } ?? []
        board.clearContents(); board.setString(text, forType: .string); let change = board.changeCount
        let source = CGEventSource(stateID: .hidSystemState); let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true); let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false); down?.flags = .maskCommand; up?.flags = .maskCommand; down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard board.changeCount == change else { return }; board.clearContents()
            let items = old.map { entries -> NSPasteboardItem in let item = NSPasteboardItem(); for (type, data) in entries { item.setData(data, forType: type) }; return item }
            if !items.isEmpty { board.writeObjects(items) }
        }
    }
    private func saveHistory() { try? FileManager.default.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(history) { try? data.write(to: historyURL, options: .atomic) } }
    func importLocalModel() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.data]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let id = "custom-" + UUID().uuidString
        do { try ModelStore.importFile(url, id: id); addCustom(Model(id: id, name: url.lastPathComponent, engine: "whisper")) }
        catch { message = error.localizedDescription }
    }
    func importRemoteModel(_ address: String) {
        guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { message = "Enter a valid HTTP(S) model URL."; return }
        let model = Model(id: "custom-" + UUID().uuidString, name: url.lastPathComponent, engine: "whisper", url: url)
        addCustom(model); download(model)
    }
    private func addCustom(_ model: Model) {
        models.append(model)
        let custom = models.filter { $0.id.hasPrefix("custom-") }
        if let data = try? JSONEncoder().encode(custom) { UserDefaults.standard.set(data, forKey: "customModels") }
    }
    func download(_ model: Model) { guard busyModel == nil else { return }; busyModel = model.id; Task { do { try await ModelStore.download(model) } catch { message = error.localizedDescription }; busyModel = nil; warmSelected(); objectWillChange.send() } }
}
struct HistoryEntry: Codable, Identifiable { var id = UUID(); let text: String; let date: Date }
