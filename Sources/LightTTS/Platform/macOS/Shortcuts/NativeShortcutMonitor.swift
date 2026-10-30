import AppKit
import Carbon
import LightTTSRuntime

@MainActor
final class NativeShortcutMonitor: ShortcutMonitoring {
    private let monitor = HotkeyMonitor()
    var onEvent: ((ShortcutEvent) -> Void)?

    init() {
        monitor.captureSuspended = { false }
        monitor.onShortcut = { [weak self] down in if down { self?.onEvent?(.toggle) } }
        monitor.onPush = { [weak self] down in self?.onEvent?(down ? .pushDown : .pushUp) }
        monitor.onMouse = { [weak self] down in self?.onEvent?(down ? .mouseDown : .mouseUp) }
        monitor.onEscape = { [weak self] in self?.onEvent?(.cancel) }
    }

    func install(_ bindings: ShortcutBindings) -> ShortcutRegistrationResult {
        var shortcuts: [UInt32: Shortcut] = [:]
        var mouse = -1
        for binding in bindings.bindings where binding.enabled {
            switch (binding.action, binding.input) {
            case (.toggle, .keyboard(let code, let flags)):
                shortcuts[1] = Shortcut(
                    code: Int(code), flags: NSEvent.ModifierFlags(rawValue: UInt(flags)))
            case (.pushToTalk, .keyboard(let code, let flags)):
                shortcuts[2] = Shortcut(
                    code: Int(code), flags: NSEvent.ModifierFlags(rawValue: UInt(flags)))
            case (.cancel, .keyboard(let code, let flags)):
                shortcuts[3] = Shortcut(
                    code: Int(code), flags: NSEvent.ModifierFlags(rawValue: UInt(flags)))
            case (.mouse, .mouse(let button)): mouse = button
            default: break
            }
        }
        monitor.configuredShortcuts = shortcuts
        monitor.configuredMouseButton = mouse
        return monitor.install() ? .installed : .unavailable
    }

    func stop() { monitor.stop() }
    func setCancellationAvailable(_ available: Bool) { monitor.setRecording(available) }

    func validate(_ binding: ShortcutBinding) -> ShortcutValidation {
        guard case .keyboard(let code, let flags) = binding.input else { return .valid }
        let shortcut = Shortcut(
            code: Int(code), flags: NSEvent.ModifierFlags(rawValue: UInt(flags)))
        guard !shortcut.modifierOnly else { return .valid }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(code), shortcut.carbonFlags, EventHotKeyID(signature: 0x4c545453, id: 99),
            GetApplicationEventTarget(), 0, &ref)
        if let ref { UnregisterEventHotKey(ref) }
        if status == noErr { return .valid }
        return .invalid(
            status == eventHotKeyExistsErr ? "Shortcut already in use" : "Shortcut unavailable")
    }
}
