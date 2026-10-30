import AppKit
import SwiftUI
@MainActor final class MenuBarController: NSObject, NSWindowDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let popover = NSPopover()
    private var window: NSWindow?
    init(app: AppController) {
        self.app = app; status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LightTTS")
        status.button?.target = self; status.button?.action = #selector(toggle)
        popover.behavior = .transient; updateContent(attached: true)
    }
    private func updateContent(attached: Bool) {
        let view = SettingsView(controller: app, detach: { [weak self] in self?.switchPresentation() }, attached: attached)
        if attached { popover.contentViewController = NSHostingController(rootView: view) }
        else { window?.contentView = NSHostingView(rootView: view) }
    }
    @objc private func toggle() { if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) } else if popover.isShown { popover.performClose(nil) } else if let button = status.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) } }
    private func switchPresentation() {
        if let existing = window { existing.orderOut(nil); window = nil; updateContent(attached: true); toggle() }
        else { popover.performClose(nil); let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 440), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false); w.title = "LightTTS"; w.isReleasedWhenClosed = false; w.delegate = self; window = w; updateContent(attached: false); w.center(); w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    func windowWillClose(_ notification: Notification) { window = nil; updateContent(attached: true) }
}
