import AppKit
import SwiftUI
import AVFoundation
import LightTTSCore

@MainActor final class MenuBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let app: AppController
    private let status: NSStatusItem
    private let popover = NSPopover()
    private var window: NSWindow?
    private var compactHost: NSHostingController<AnyView>?
    private var settingsHost: NSHostingView<AnyView>?
    private let compactData = CompactMenuData()
    private var previousApp: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    private var openingSettings = false

    init(app: AppController) {
        self.app = app
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApp = frontmost }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frontmostApplicationChanged(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        status.button?.image = makeStatusImage()
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        popover.behavior = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_MENU"] == "1" ? .applicationDefined : .transient
        popover.animates = false
        popover.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidHide), name: NSApplication.didHideNotification, object: NSApp)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidUnhide), name: NSApplication.didUnhideNotification, object: NSApp)
        if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] {
            popover.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
        if CommandLine.arguments.contains("--settings-window") { openSettingsWindow() }
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
        let event = NSApp.currentEvent
        if UserDefaults.standard.bool(forKey: "recordOnMenubarClick"), event?.type == .leftMouseUp, event?.modifierFlags.contains(.option) != true {
            if popover.isShown { popover.performClose(nil) }; app.toggleRecording()
        } else if popover.isShown { popover.performClose(nil) }
        else { UITrace.begin("popover"); showCompact() }
    }
    private func showCompact() {
        guard let button = status.button else { return }
        compactData.load(models: app.models)
        updateContent()
        if let appearance = NSApp.appearance { button.appearance = appearance }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : frontmost
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        UITrace.end("popover")
    }
    func openSettingsWindow() {
        UITrace.begin("settings-window")
        openingSettings = true
        popover.performClose(nil)
        openingSettings = false
        NSApp.activate(ignoringOtherApps: true)
        if let window { if !window.isVisible || window.isMiniaturized { settingsHost?.rootView = AnyView(SettingsView(controller: app).ignoresSafeArea()) }; if window.isMiniaturized { window.deminiaturize(nil) }; window.makeKeyAndOrderFront(nil) }
        else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 508), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.minSize = NSSize(width: 750, height: 508)
            w.title = "LightTTS"; w.titleVisibility = .hidden; w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false; w.delegate = self; window = w
            let host = NSHostingView(rootView: AnyView(SettingsView(controller: app).ignoresSafeArea()))
            settingsHost = host
            host.sizingOptions = []; w.contentView = host
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
    func popoverDidClose(_ notification: Notification) {
        compactHost?.rootView = AnyView(EmptyView())
        defer { previousApp = nil }
        guard !openingSettings, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else { return }
        previousApp?.activate()
    }
    private func performRecordingAction() {
        let state = app.state
        let target = previousApp
        let recordingDate = app.started
        popover.performClose(nil) // popoverDidClose restores the previously active app
        if state == "idle" || state == "done" || state == "recording" {
            Task { @MainActor [weak self] in
                // Activation is asynchronous. Stop must capture the external field,
                // just as starting must leave the menu before taking the microphone.
                if let target, !target.isTerminated {
                    target.activate()
                    for _ in 0..<10 {
                        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
                        try? await Task.sleep(nanoseconds: 50_000_000)
                    }
                }
                guard let self, self.app.state == state || (state == "done" && self.app.state == "idle"), self.app.started == recordingDate else { return }
                if state == "recording" { self.app.stop() }
                else { self.app.toggleRecording() }
            }
        } else if ["starting", "loading", "processing"].contains(state) {
            app.cancel()
        }
    }
    private func updateContent() {
        let view = CompactMenuView(controller: app, openSettings: { [weak self] in self?.openSettingsWindow() }, recordingAction: { [weak self] in self?.performRecordingAction() }, cancelRecording: { [weak self] in self?.popover.performClose(nil); self?.app.cancel() }, data: compactData)
        let root: AnyView
        if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] {
            root = AnyView(view.environment(\.colorScheme, appearance == "light" ? .light : .dark))
        } else { root = AnyView(view) }
        if let compactHost { compactHost.rootView = root; popover.contentViewController = compactHost; return }
        let hosting = NSHostingController(rootView: root)
        if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] { hosting.view.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua) }
        compactHost = hosting; popover.contentViewController = hosting
    }
    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        guard let active = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              active.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastExternalApp = active
    }
    @objc private func applicationDidHide() { compactHost?.rootView = AnyView(EmptyView()); settingsHost?.rootView = AnyView(EmptyView()) }
    @objc private func applicationDidUnhide() {
        if popover.isShown { compactData.load(models: app.models); updateContent() }
        if let window, window.isVisible && !window.isMiniaturized { settingsHost?.rootView = AnyView(SettingsView(controller: app).ignoresSafeArea()) }
    }
    func windowWillClose(_ notification: Notification) { settingsHost?.rootView = AnyView(EmptyView()) }
    func windowDidMiniaturize(_ notification: Notification) { settingsHost?.rootView = AnyView(EmptyView()) }
    func windowDidDeminiaturize(_ notification: Notification) { settingsHost?.rootView = AnyView(SettingsView(controller: app).ignoresSafeArea()) }
}
