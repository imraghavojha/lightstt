import AppKit
import SwiftUI
import AVFoundation
import LightTTSCore

@MainActor final class MenuBarController: NSObject, NSWindowDelegate, NSMenuDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let popover = NSPopover()
    private var window: NSWindow?
    private let menu = NSMenu()

    init(app: AppController) {
        self.app = app
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.button?.image = makeStatusImage()
        menu.delegate = self
        status.menu = menu
        popover.behavior = .transient
        updateContent(attached: true)
        if ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_MENU"] == "1" {
            DispatchQueue.main.async { [weak self] in
                guard let self, let button = self.status.button else { return }
                button.appearance = NSApp.appearance
                NSApp.activate(ignoringOtherApps: true)
                self.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: button)
            }
        }
    }

    private func makeStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 9, y: 14.25))
            path.line(to: NSPoint(x: 15, y: 3.25))
            path.line(to: NSPoint(x: 3, y: 3.25))
            path.close()
            path.lineWidth = 2.5
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LightTTS"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add("Toggle Recording", action: #selector(toggleRecording))
        let transcribe = add("Transcribe File…", action: nil); transcribe.isEnabled = false
        add("History…", action: #selector(history))
        let settings = add("Settings…", action: #selector(settings), key: ","); settings.keyEquivalentModifierMask = .command
        menu.addItem(.separator())
        let selectedInput = UserDefaults.standard.string(forKey: "inputDeviceUID") ?? ""
        let devices = InputDevice.available
        let defaultName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Microphone"
        let deviceName = devices.first(where: { $0.id == selectedInput })?.name ?? "\(defaultName) (Default)"
        let input = add(deviceName, action: nil)
        let inputs = NSMenu()
        let defaultInput = NSMenuItem(title: "\(defaultName) (Default)", action: #selector(selectInput(_:)), keyEquivalent: "")
        defaultInput.target = self; defaultInput.representedObject = ""; defaultInput.state = selectedInput.isEmpty ? .on : .off
        inputs.addItem(defaultInput)
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectInput(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = device.id; item.state = selectedInput == device.id ? .on : .off
            inputs.addItem(item)
        }
        input.submenu = inputs
        let modeItem = add("Voice to text", action: nil)
        let modes = NSMenu()
        let voice = NSMenuItem(title: "Voice to text", action: #selector(selectVoiceMode), keyEquivalent: "")
        voice.target = self; voice.state = .on; modes.addItem(voice)
        for name in ["Pro", "Default"] {
            let item = NSMenuItem(title: name, action: #selector(unavailableMode(_:)), keyEquivalent: "")
            item.target = self; modes.addItem(item)
        }
        modeItem.submenu = modes
        menu.addItem(.separator())
        let version = add("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1")", action: nil); version.isEnabled = false
        add("Check for Updates…", action: #selector(checkForUpdates))
        let quit = add("Quit", action: #selector(quit), key: "q"); quit.keyEquivalentModifierMask = .command
    }
    @discardableResult private func add(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    @objc private func toggleRecording() { if app.state == "recording" { app.stop() } else if app.state == "idle" { app.start() } }
    @objc private func selectInput(_ sender: NSMenuItem) { guard let id = sender.representedObject as? String else { return }; UserDefaults.standard.set(id, forKey: "inputDeviceUID") }
    @objc private func selectVoiceMode() { }
    @objc private func unavailableMode(_ sender: NSMenuItem) {
        let alert = NSAlert(); alert.messageText = "\(sender.title) is unavailable"; alert.informativeText = "LightTTS currently supports Voice to text."; alert.runModal()
    }
    @objc private func checkForUpdates() { if let url = URL(string: "https://github.com/imraghavojha/lighttts/releases") { NSWorkspace.shared.open(url) } }
    @objc private func history() { showSettings("Library") }
    @objc private func settings() { showSettings(nil) }
    @objc private func modelsSettings() { showSettings("Models") }
    @objc private func quit() { NSApp.terminate(nil) }
    private func showSettings(_ selection: String?) {
        if let selection { app.settingsSelection = selection }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else if let button = status.button { updateContent(attached: true); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
    }
    private func updateContent(attached: Bool) {
        let view = SettingsView(controller: app, detach: { [weak self] in self?.switchPresentation() }, attached: attached)
        if attached { popover.contentViewController = NSHostingController(rootView: view) }
        else { window?.contentView = NSHostingView(rootView: view) }
    }
    private func switchPresentation() {
        if let existing = window { existing.orderOut(nil); window = nil; updateContent(attached: true); showSettings(nil) }
        else { popover.performClose(nil); let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 440), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false); w.title = "LightTTS"; w.isReleasedWhenClosed = false; w.delegate = self; window = w; updateContent(attached: false); w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func windowWillClose(_ notification: Notification) { window = nil; updateContent(attached: true) }
}
