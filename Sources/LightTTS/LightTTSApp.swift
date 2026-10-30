import AppKit
@main struct LightTTSApp {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let controller = AppController(); let menu = MenuBarController(app: controller)
        withExtendedLifetime((controller, menu)) { app.run() }
    }
}
