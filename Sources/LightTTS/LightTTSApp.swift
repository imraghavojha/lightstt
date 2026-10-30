import AppKit
import Foundation
@main struct LightTTSApp {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let controller = AppController(); let menu = MenuBarController(app: controller)
        if let marker = ProcessInfo.processInfo.environment["LIGHTTTS_LAUNCH_MARKER"] { try? Data("ready".utf8).write(to: URL(fileURLWithPath: marker), options: .atomic) }
        DispatchQueue.main.async {
            if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_REQUEST_PERMISSIONS"] == "1" { controller.requestPermissions() }
            else { controller.installHotkey() }
        }
        withExtendedLifetime((controller, menu)) { app.run() }
    }
}
