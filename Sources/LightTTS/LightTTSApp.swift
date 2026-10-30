import AppKit
import AVFoundation
import ApplicationServices
import Foundation

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    private var hotkeyReady = false
    private var catalogReady = false
    private var isUITest: Bool {
        let env = ProcessInfo.processInfo.environment
        return CommandLine.arguments.contains("--ui-fixture") || env["LIGHTTTS_UI_SHOT_STATE"] != nil || env["LIGHTTTS_UI_SHOT_MENU"] == "1" || env["LIGHTTTS_TEST_AUDIO"] != nil
    }
    private func writeReadyMarker() {
        guard hotkeyReady && catalogReady, let marker = ProcessInfo.processInfo.environment["LIGHTTTS_LAUNCH_MARKER"] else { return }
        try? Data("ready".utf8).write(to: URL(fileURLWithPath: marker), options: .atomic)
    }
    init(controller: AppController) { self.controller = controller }
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        #endif
        if isUITest || CommandLine.arguments.contains("--models-window") { hotkeyReady = true; writeReadyMarker(); return }
        hotkeyReady = controller.installHotkey(); LaunchTrace.mark(hotkeyReady ? "hotkey-installed" : "hotkey-unavailable"); writeReadyMarker()
    }
    func applicationDidBecomeActive(_ notification: Notification) { if !isUITest && !CommandLine.arguments.contains("--models-window") && AXIsProcessTrusted() { hotkeyReady = controller.installHotkey(); writeReadyMarker() } }
    func catalogDidLoad() { catalogReady = true; writeReadyMarker() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var replied = false
        let reply = { if !replied { replied = true; sender.reply(toApplicationShouldTerminate: true) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: reply)
        controller.beginQuit()
        Task { await controller.finishQuit(); reply() }
        return .terminateLater
    }
    #if DEBUG
    @objc private func openURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue, let url = URL(string: value), url.scheme == "lighttts", url.host == "toggle" else { return }
        controller.testURLToggle()
    }
    #endif
}
@main struct LightTTSApp {
    @MainActor static func main() {
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.lighttts.app").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) { other.activate(options: [.activateIgnoringOtherApps]); return }
        LaunchTrace.mark("main-entry")
        let app = NSApplication.shared; app.setActivationPolicy(.accessory); LaunchTrace.mark("appkit-ready")
        if let appearance = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_APPEARANCE"] { app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua) }
        let controller = AppController(); let menu = MenuBarController(app: controller); let delegate = AppDelegate(controller: controller); app.delegate = delegate
        controller.onCatalogReady = { [weak delegate, weak controller] in
            delegate?.catalogDidLoad()
            if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUTOSTART"] == "1" {
                controller?.start()
                if let value = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUTOSTOP_SECONDS"], let delay = Double(value), delay > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak controller] in controller?.stop() }
                }
            }
        }
        if let state = ProcessInfo.processInfo.environment["LIGHTTTS_UI_SHOT_STATE"] { controller.showPreviewState(state) }
        LaunchTrace.mark("status-item-created")
        if CommandLine.arguments.contains("--light-appearance") { app.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark-appearance") { app.appearance = NSAppearance(named: .darkAqua) }
        if CommandLine.arguments.contains("--models-window") { DispatchQueue.main.async { controller.settingsSelection = "Models"; menu.openSettingsWindow() } }
        else if !CommandLine.arguments.contains("--ui-fixture") && ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] == nil && (!AXIsProcessTrusted() || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized) { DispatchQueue.main.async { controller.settingsSelection = "Configuration"; menu.openSettingsWindow() } }
        withExtendedLifetime((controller, menu, delegate)) { app.run() }
    }
}

enum LaunchTrace {
    static func mark(_ stage: String) {
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" || ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { fputs("LightTTS trace: \(stage) mach=\(mach_absolute_time())\n", stderr) }
    }
}
