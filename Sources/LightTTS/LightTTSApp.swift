import AppKit
import AVFoundation
import ApplicationServices
import Foundation

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    init(controller: AppController) { self.controller = controller }
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openURL(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        #endif
        controller.installHotkey()
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
    func applicationDidBecomeActive(_ notification: Notification) { if AXIsProcessTrusted() && CGPreflightListenEventAccess() { controller.installHotkey() } }
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
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let controller = AppController(); let menu = MenuBarController(app: controller); let delegate = AppDelegate(controller: controller); app.delegate = delegate
        if let marker = ProcessInfo.processInfo.environment["LIGHTTTS_LAUNCH_MARKER"] { try? Data("ready".utf8).write(to: URL(fileURLWithPath: marker), options: .atomic) }
        withExtendedLifetime((controller, menu, delegate)) { app.run() }
    }
}
