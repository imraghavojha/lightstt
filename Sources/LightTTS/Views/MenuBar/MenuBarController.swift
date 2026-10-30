import AppKit
import SwiftUI
import AVFoundation
import LightTTSCore

@MainActor final class MenuBarController: NSObject, NSWindowDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let popover = NSPopover()
    private var window: NSWindow?

    init(app: AppController) {
        self.app = app
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.button?.image = makeStatusImage()
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        popover.behavior = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_MENU"] == "1" ? .applicationDefined : .transient
        popover.animates = false
        updateContent(attached: true)
        if ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_MENU"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showCompact() }
        }
    }

    private func makeStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            // Draw both contours explicitly so the inner corners are rounded too.
            path.move(to: NSPoint(x: 9, y: 15.75))
            path.curve(to: NSPoint(x: 7.35, y: 14.55), controlPoint1: NSPoint(x: 8.3, y: 15.75), controlPoint2: NSPoint(x: 7.8, y: 15.35))
            path.curve(to: NSPoint(x: 1.95, y: 4.45), controlPoint1: NSPoint(x: 4.8, y: 9.8), controlPoint2: NSPoint(x: 1.25, y: 5.95))
            path.curve(to: NSPoint(x: 3.5, y: 2.25), controlPoint1: NSPoint(x: 1.3, y: 3.2), controlPoint2: NSPoint(x: 2.05, y: 2.25))
            path.line(to: NSPoint(x: 14.5, y: 2.25))
            path.curve(to: NSPoint(x: 16.05, y: 4.45), controlPoint1: NSPoint(x: 15.95, y: 2.25), controlPoint2: NSPoint(x: 16.7, y: 3.2))
            path.curve(to: NSPoint(x: 10.65, y: 14.55), controlPoint1: NSPoint(x: 16.75, y: 5.95), controlPoint2: NSPoint(x: 13.2, y: 9.8))
            path.curve(to: NSPoint(x: 9, y: 15.75), controlPoint1: NSPoint(x: 10.2, y: 15.35), controlPoint2: NSPoint(x: 9.7, y: 15.75))
            path.close()
            path.move(to: NSPoint(x: 9, y: 12.3))
            path.curve(to: NSPoint(x: 8.4, y: 11.85), controlPoint1: NSPoint(x: 8.75, y: 12.3), controlPoint2: NSPoint(x: 8.55, y: 12.1))
            path.line(to: NSPoint(x: 5.05, y: 5.35))
            path.curve(to: NSPoint(x: 6.05, y: 3.75), controlPoint1: NSPoint(x: 4.5, y: 4.3), controlPoint2: NSPoint(x: 5.0, y: 3.75))
            path.line(to: NSPoint(x: 11.95, y: 3.75))
            path.curve(to: NSPoint(x: 12.95, y: 5.35), controlPoint1: NSPoint(x: 13.0, y: 3.75), controlPoint2: NSPoint(x: 13.5, y: 4.3))
            path.line(to: NSPoint(x: 9.6, y: 11.85))
            path.curve(to: NSPoint(x: 9, y: 12.3), controlPoint1: NSPoint(x: 9.45, y: 12.1), controlPoint2: NSPoint(x: 9.25, y: 12.3))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LightTTS"
        return image
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) }
        else { showCompact() }
    }
    private func showCompact() {
        guard let button = status.button else { return }
        if let appearance = NSApp.appearance { button.appearance = appearance }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    private func showSettings() {
        popover.performClose(nil)
        if let window { window.makeKeyAndOrderFront(nil) }
        else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 440), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "LightTTS"; w.isReleasedWhenClosed = false; w.delegate = self; window = w
            updateContent(attached: false); w.center(); w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func updateContent(attached: Bool) {
        if attached {
            popover.contentViewController = NSHostingController(rootView: CompactMenuView(controller: app, openSettings: { [weak self] in self?.showSettings() }))
        } else {
            window?.contentView = NSHostingView(rootView: SettingsView(controller: app, detach: { [weak self] in self?.switchPresentation() }, attached: false))
        }
    }
    private func switchPresentation() {
        window?.orderOut(nil); window = nil
        showCompact()
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
