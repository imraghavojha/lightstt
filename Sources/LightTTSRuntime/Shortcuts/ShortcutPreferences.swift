import Foundation

@MainActor
public final class ShortcutPreferences {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func bindings() -> ShortcutBindings {
        let toggleCode = defaults.bool(forKey: "rightOption") ? 61 : integer("hotkeyCode", 49)
        let toggleFlags =
            defaults.bool(forKey: "rightOption") ? 0 : integer("hotkeyModifiers", 1 << 19)
        return ShortcutBindings([
            ShortcutBinding(
                action: .toggle,
                input: .keyboard(
                    keyCode: UInt16(clamping: toggleCode), modifiers: UInt64(clamping: toggleFlags)),
                enabled: true),
            ShortcutBinding(
                action: .pushToTalk,
                input: .keyboard(
                    keyCode: UInt16(clamping: integer("pushHotkeyCode", 49)),
                    modifiers: UInt64(
                        clamping: integer("pushHotkeyModifiers", (1 << 19) | (1 << 17)))),
                enabled: defaults.bool(forKey: "pushShortcutEnabled")),
            ShortcutBinding(
                action: .cancel,
                input: .keyboard(
                    keyCode: UInt16(clamping: integer("cancelHotkeyCode", 53)),
                    modifiers: UInt64(clamping: integer("cancelHotkeyModifiers", 0))), enabled: true
            ),
            ShortcutBinding(
                action: .mouse, input: .mouse(button: integer("mouseShortcut", -1)),
                enabled: integer("mouseShortcut", -1) >= 0),
        ])
    }

    private func integer(_ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? fallback
    }

    public func save(_ binding: ShortcutBinding) {
        switch (binding.action, binding.input) {
        case (.toggle, .keyboard(let code, let flags)),
            (.pushToTalk, .keyboard(let code, let flags)),
            (.cancel, .keyboard(let code, let flags)):
            let keys = keyboardKeys(binding.action)
            defaults.set(Int(code), forKey: keys.0)
            defaults.set(Int(clamping: flags), forKey: keys.1)
            if binding.action == .toggle { defaults.set(false, forKey: "rightOption") }
            if binding.action == .pushToTalk {
                defaults.set(binding.enabled, forKey: "pushShortcutEnabled")
            }
        case (.mouse, .mouse(let button)):
            defaults.set(binding.enabled ? button : -1, forKey: "mouseShortcut")
        default:
            break
        }
    }

    public func reset(_ action: ShortcutAction) {
        if action == .mouse {
            defaults.removeObject(forKey: "mouseShortcut")
        } else {
            let keys = keyboardKeys(action)
            defaults.removeObject(forKey: keys.0)
            defaults.removeObject(forKey: keys.1)
            if action == .toggle { defaults.set(false, forKey: "rightOption") }
            if action == .pushToTalk { defaults.set(false, forKey: "pushShortcutEnabled") }
        }
    }

    private func keyboardKeys(_ action: ShortcutAction) -> (String, String) {
        switch action {
        case .toggle: return ("hotkeyCode", "hotkeyModifiers")
        case .pushToTalk: return ("pushHotkeyCode", "pushHotkeyModifiers")
        case .cancel: return ("cancelHotkeyCode", "cancelHotkeyModifiers")
        case .mouse: return ("", "")
        }
    }

    public static func defaultBinding(_ action: ShortcutAction) -> ShortcutBinding {
        switch action {
        case .toggle:
            return ShortcutBinding(
                action: action, input: .keyboard(keyCode: 49, modifiers: 1 << 19), enabled: true)
        case .pushToTalk:
            return ShortcutBinding(
                action: action, input: .keyboard(keyCode: 49, modifiers: (1 << 19) | (1 << 17)),
                enabled: false)
        case .cancel:
            return ShortcutBinding(
                action: action, input: .keyboard(keyCode: 53, modifiers: 0), enabled: true)
        case .mouse:
            return ShortcutBinding(action: action, input: .mouse(button: -1), enabled: false)
        }
    }
}
