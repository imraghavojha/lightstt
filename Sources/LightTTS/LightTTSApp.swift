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
        return env["LIGHTTTS_UI_SHOT_STATE"] != nil || env["LIGHTTTS_UI_SHOT_MENU"] == "1" || env["LIGHTTTS_TEST_AUDIO"] != nil
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
        if isUITest { hotkeyReady = true; writeReadyMarker(); return }
        hotkeyReady = controller.installHotkey(); LaunchTrace.mark(hotkeyReady ? "hotkey-installed" : "hotkey-unavailable"); writeReadyMarker()
        if !UserDefaults.standard.bool(forKey: "permissionsOnboardingRequested") {
            UserDefaults.standard.set(true, forKey: "permissionsOnboardingRequested")
            if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
            if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
            #if DEBUG
            let testAudio = ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"] != nil || ProcessInfo.processInfo.environment["LIGHTTTS_TEST_WAV"] != nil
            #else
            let testAudio = false
            #endif
            if !testAudio && AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined { Task { _ = await AVCaptureDevice.requestAccess(for: .audio) } }
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { if !isUITest && AXIsProcessTrusted() && CGPreflightListenEventAccess() { hotkeyReady = controller.installHotkey(); writeReadyMarker() } }
    func catalogDidLoad() { catalogReady = true; writeReadyMarker() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { await controller.prepareToQuit(); sender.reply(toApplicationShouldTerminate: true) }
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
        withExtendedLifetime((controller, menu, delegate)) { app.run() }
    }
}

enum LaunchTrace {
    static func mark(_ stage: String) {
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS launch: \(stage) uptime=\(ProcessInfo.processInfo.systemUptime)\n", stderr) }
    }
}
