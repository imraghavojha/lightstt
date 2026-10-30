import AppKit
import SwiftUI
import AVFoundation
import LightTTSCore

@MainActor final class MenuBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let popover = NSPopover()
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    private var openingSettings = false
    private var expanded = false

    init(app: AppController) {
        self.app = app
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        status.button?.image = makeStatusImage()
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        popover.behavior = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_MENU"] == "1" ? .applicationDefined : .transient
        popover.animates = false
        popover.delegate = self
        if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] {
            popover.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        if CommandLine.arguments.contains("--settings-window") { showDetachedSettings() }
        else if CommandLine.arguments.contains("--settings-popover") {
            expanded = true; updateContent(attached: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showCompact() }
        }
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
            path.curve(to: NSPoint(x: 1.5, y: 4.75), controlPoint1: NSPoint(x: 5.15, y: 10.9), controlPoint2: NSPoint(x: 1.5, y: 6.2))
            path.curve(to: NSPoint(x: 2.5, y: 2.25), controlPoint1: NSPoint(x: 1.0, y: 3.1), controlPoint2: NSPoint(x: 1.25, y: 2.25))
            path.line(to: NSPoint(x: 15.5, y: 2.25))
            path.curve(to: NSPoint(x: 16.5, y: 4.75), controlPoint1: NSPoint(x: 16.75, y: 2.25), controlPoint2: NSPoint(x: 17.0, y: 3.1))
            path.curve(to: NSPoint(x: 10.65, y: 14.55), controlPoint1: NSPoint(x: 16.5, y: 6.2), controlPoint2: NSPoint(x: 12.85, y: 10.9))
            path.curve(to: NSPoint(x: 9, y: 15.75), controlPoint1: NSPoint(x: 10.2, y: 15.35), controlPoint2: NSPoint(x: 9.7, y: 15.75))
            path.close()
            path.move(to: NSPoint(x: 9, y: 12.3))
            path.curve(to: NSPoint(x: 8.4, y: 11.85), controlPoint1: NSPoint(x: 8.75, y: 12.3), controlPoint2: NSPoint(x: 8.55, y: 12.1))
            path.curve(to: NSPoint(x: 4.7, y: 5.35), controlPoint1: NSPoint(x: 6.6, y: 9.7), controlPoint2: NSPoint(x: 5.05, y: 7.5))
            path.curve(to: NSPoint(x: 7.5, y: 4.23), controlPoint1: NSPoint(x: 4.4, y: 4.5), controlPoint2: NSPoint(x: 6.2, y: 4.23))
            path.line(to: NSPoint(x: 10.5, y: 4.23))
            path.curve(to: NSPoint(x: 13.3, y: 5.35), controlPoint1: NSPoint(x: 12.6, y: 4.23), controlPoint2: NSPoint(x: 13.6, y: 4.5))
            path.curve(to: NSPoint(x: 9.6, y: 11.85), controlPoint1: NSPoint(x: 12.95, y: 7.5), controlPoint2: NSPoint(x: 11.4, y: 9.7))
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
        else { expanded = false; updateContent(attached: true); showCompact() }
    }
    private func showCompact() {
        guard let button = status.button else { return }
        updateContent(attached: true)
        if let appearance = NSApp.appearance { button.appearance = appearance }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    private func showSettings() {
        // Re-anchor after changing size: resizing a shown popover can grow it
        // above the menu bar and leave the settings outside the visible screen.
        let previous = previousApp
        openingSettings = true
        popover.performClose(nil)
        previousApp = previous
        expanded = true
        updateContent(attached: true)
        if let button = status.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        openingSettings = false
    }
    private func showDetachedSettings() {
        openingSettings = true
        popover.performClose(nil)
        openingSettings = false
        if let window { window.makeKeyAndOrderFront(nil) }
        else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 508), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.title = "LightTTS"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false; w.delegate = self; window = w
            updateContent(attached: false); w.setFrame(NSRect(x: 0, y: 0, width: 750, height: 508), display: false); w.center(); w.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                for (button, x) in [(NSWindow.ButtonType.closeButton, 20.0), (.miniaturizeButton, 43.0)] {
                    if let control = w.standardWindowButton(button) {
                        let shift = control.superview?.isFlipped == true ? 5.0 : -5.0
                        control.setFrameOrigin(NSPoint(x: x, y: 3 + shift))
                    }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        defer { previousApp = nil }
        guard !openingSettings, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        previousApp?.activate()
    }
    private func updateContent(attached: Bool) {
        if attached && expanded {
            popover.contentViewController = NSHostingController(rootView: SettingsView(controller: app, detach: { [weak self] in self?.showDetachedSettings() }, attached: true))
        } else if attached {
            let view = CompactMenuView(controller: app, openSettings: { [weak self] in self?.showSettings() })
            if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] {
                let hosting = NSHostingController(rootView: view.environment(\.colorScheme, appearance == "light" ? .light : .dark))
                hosting.view.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
                popover.contentViewController = hosting
            } else {
                popover.contentViewController = NSHostingController(rootView: view)
            }
        } else {
            let host = NSHostingView(rootView: SettingsView(controller: app, detach: { [weak self] in self?.switchPresentation() }, attached: false).ignoresSafeArea())
            host.sizingOptions = []; window?.contentView = host
        }
    }
    func openSettingsWindow() { showDetachedSettings() }
    private func switchPresentation() {
        window?.orderOut(nil); window = nil
        expanded = true; updateContent(attached: true); showCompact()
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
