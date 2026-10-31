import AppKit
import SwiftUI
import AVFoundation
import LightTTSCore

enum SettingsWindowSizing {
    static let minimum = NSSize(width: 750, height: 508)
    static func clamped(_ size: NSSize) -> NSSize {
        NSSize(width: max(minimum.width, size.width), height: max(minimum.height, size.height))
    }
}

/// The status item uses a native menu. A menu does not activate LightTTS, so opening it
/// never raises the Settings window, and the app being dictated into stays frontmost.
@MainActor final class MenuBarController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let menu = NSMenu()
    private var window: NSWindow?
    private var settingsHost: NSHostingView<AnyView>?
    private var devices: [InputDevice] = []
    private var systemDefaultDevice: InputDevice?
    private var observers: [NSObjectProtocol] = []

    init(app: AppController) {
        self.app = app
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        status.button?.image = Self.statusImage
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        menu.delegate = self
        menu.autoenablesItems = false
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidHide), name: NSApplication.didHideNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidUnhide), name: NSApplication.didUnhideNotification, object: NSApp)
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDevices() }
            })
        }
        refreshDevices()
        if CommandLine.arguments.contains("--settings-window") { openSettingsWindow() }
    }

    static var statusImage: NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LightTTS")?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if UserDefaults.standard.bool(forKey: "recordOnMenubarClick"), event?.type == .leftMouseDown, event?.modifierFlags.contains(.option) != true {
            app.toggleRecording()
            return
        }
        // Attach the menu only for this click so the record-on-click option keeps working.
        status.menu = menu
        status.button?.performClick(nil)
        status.menu = nil
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        switch app.state {
        case "recording":
            menu.addItem(item("Stop Recording", detail: ShortcutButton.displayName(.toggle), action: #selector(toggleRecording)))
            menu.addItem(item("Cancel Recording", detail: ShortcutButton.displayName(.cancel), action: #selector(cancelRecording)))
        case "starting":
            menu.addItem(disabled("Starting…"))
            menu.addItem(item("Cancel Recording", detail: ShortcutButton.displayName(.cancel), action: #selector(cancelRecording)))
        case "loading", "processing":
            menu.addItem(disabled(app.state == "loading" ? "Loading model…" : "Transcribing…"))
            menu.addItem(item("Cancel", detail: ShortcutButton.displayName(.cancel), action: #selector(cancelRecording)))
        case "error":
            menu.addItem(item("Dismiss Error", detail: nil, action: #selector(cancelRecording)))
            menu.addItem(item("Start Recording", detail: ShortcutButton.displayName(.toggle), action: #selector(toggleRecording)))
        default:
            menu.addItem(item("Start Recording", detail: ShortcutButton.displayName(.toggle), action: #selector(toggleRecording)))
        }
        menu.addItem(.separator())
        menu.addItem(modelItem())
        menu.addItem(microphoneItem())
        menu.addItem(.separator())
        let settings = item("Settings…", detail: nil, action: #selector(openSettingsFromMenu))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = item("Quit LightTTS", detail: nil, action: #selector(quitApp))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    func menuDidClose(_ menu: NSMenu) {
        // Pick up a changed system default input for the next open, off the main thread.
        refreshDevices()
    }

    private func modelItem() -> NSMenuItem {
        let selected = UserDefaults.standard.string(forKey: "selectedModel") ?? ModelDefaults.selectedModel
        let installed = app.models.filter { ModelStore.exists($0) }
        let current = installed.first { $0.id == selected }
        let parent = item("Model", detail: current?.name ?? "None", action: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        if installed.isEmpty {
            submenu.addItem(item("Download a Model…", detail: nil, action: #selector(openModelsSettings)))
        }
        for model in installed {
            let entry = item(model.name, detail: nil, action: #selector(selectModel(_:)))
            entry.representedObject = model.id
            entry.state = model.id == selected ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func microphoneItem() -> NSMenuItem {
        let selected = UserDefaults.standard.string(forKey: "inputDeviceUID") ?? ""
        let choices = InputDevice.choices(available: devices, systemDefault: systemDefaultDevice)
        let followsDefault = selected.isEmpty || selected == systemDefaultDevice?.id
        let current = followsDefault ? choices.first : choices.first { $0.id == selected }
        let parent = item("Microphone", detail: current?.name ?? "Unavailable", action: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for device in choices {
            let entry = item(device.name, detail: nil, action: #selector(selectMicrophone(_:)))
            entry.representedObject = device.id
            entry.state = (device.id.isEmpty ? followsDefault : device.id == selected) ? .on : .off
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func item(_ title: String, detail: String?, action: Selector?) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        if let detail, !detail.isEmpty {
            let font = NSFont.menuFont(ofSize: 0)
            let style = NSMutableParagraphStyle()
            style.tabStops = [NSTextTab(textAlignment: .right, location: 236)]
            let shown = detail.count > 24 ? String(detail.prefix(23)) + "…" : detail
            let text = NSMutableAttributedString(string: title + "\t", attributes: [.font: font, .paragraphStyle: style])
            text.append(NSAttributedString(string: shown, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor]))
            entry.attributedTitle = text
            entry.toolTip = detail.count > 24 ? detail : nil
        }
        return entry
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func refreshDevices() {
        Task.detached(priority: .utility) {
            let available = InputDevice.available
            let systemDefault = InputDevice.systemDefault
            await MainActor.run { [weak self] in
                self?.devices = available
                self?.systemDefaultDevice = systemDefault
            }
        }
    }

    // MARK: Actions

    // The menu never activates LightTTS, so the app being dictated into keeps focus.
    @objc private func toggleRecording() { app.toggleRecording() }
    @objc private func cancelRecording() { app.cancel() }
    @objc private func openSettingsFromMenu() { openSettingsWindow() }
    // Goes through applicationShouldTerminate, which cancels any session, restores audio,
    // flushes history and stops the speech engine before exiting.
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func openModelsSettings() {
        app.selectSettings("Models")
        openSettingsWindow()
    }
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, UserDefaults.standard.string(forKey: "selectedModel") != id else { return }
        UserDefaults.standard.set(id, forKey: "selectedModel")
        app.reloadSelectedModel()
    }
    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        UserDefaults.standard.set(id, forKey: "inputDeviceUID")
    }

    // MARK: Settings window

    func openSettingsWindow() {
        UITrace.begin("settings-window")
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            if !window.isVisible || window.isMiniaturized { settingsHost?.rootView = settingsRoot }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 508), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.minSize = SettingsWindowSizing.minimum
            w.title = "LightTTS"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
            let host = NSHostingView(rootView: settingsRoot)
            settingsHost = host
            host.sizingOptions = []
            w.contentView = host
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let frame = screen?.visibleFrame {
                let size = NSSize(width: min(750, frame.width), height: min(508, frame.height))
                w.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height), display: false)
            }
            w.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                for (button, x) in [(NSWindow.ButtonType.closeButton, 20.0), (.miniaturizeButton, 43.0), (.zoomButton, 66.0)] {
                    if let control = w.standardWindowButton(button) {
                        let shift = control.superview?.isFlipped == true ? 5.0 : -5.0
                        control.setFrameOrigin(NSPoint(x: x, y: 3 + shift))
                    }
                }
            }
        }
        UITrace.end("settings-window")
    }
    private var settingsRoot: AnyView { AnyView(SettingsView(controller: app).ignoresSafeArea()) }

    @objc private func applicationDidHide() { settingsHost?.rootView = AnyView(EmptyView()) }
    @objc private func applicationDidUnhide() {
        if let window, window.isVisible && !window.isMiniaturized { settingsHost?.rootView = settingsRoot }
    }
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize { SettingsWindowSizing.clamped(frameSize) }
    func windowWillClose(_ notification: Notification) { settingsHost?.rootView = AnyView(EmptyView()) }
    func windowDidMiniaturize(_ notification: Notification) { settingsHost?.rootView = AnyView(EmptyView()) }
    func windowDidDeminiaturize(_ notification: Notification) { settingsHost?.rootView = settingsRoot }
}
