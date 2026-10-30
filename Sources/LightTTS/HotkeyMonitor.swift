import AppKit
import ApplicationServices
import Carbon
import LightTTSCore

extension Notification.Name { static let shortcutsChanged = Notification.Name("LightTTSShortcutsChanged"); static let shortcutCaptureChanged = Notification.Name("LightTTSShortcutCaptureChanged") }

struct Shortcut {
    let code: Int; let flags: NSEvent.ModifierFlags
    var modifierOnly: Bool { [54, 55, 56, 60, 58, 61, 59, 62].contains(code) }
    var carbonFlags: UInt32 { (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.option) ? UInt32(optionKey) : 0) | (flags.contains(.control) ? UInt32(controlKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0) }
    static func load(_ key: String, _ modifiers: String, _ fallback: Int, _ defaultFlags: NSEvent.ModifierFlags) -> Shortcut {
        let d = SettingsDefaults.store
        if key == "hotkeyCode" && d.bool(forKey: "rightOption") { return Shortcut(code: 61, flags: []) }
        return Shortcut(code: d.object(forKey: key) as? Int ?? fallback, flags: NSEvent.ModifierFlags(rawValue: UInt(d.object(forKey: modifiers) as? Int ?? Int(defaultFlags.rawValue))) )
    }
    static var toggle: Shortcut { load("hotkeyCode", "hotkeyModifiers", 49, .option) }
    static var push: Shortcut { load("pushHotkeyCode", "pushHotkeyModifiers", 49, [.option, .shift]) }
    static var cancel: Shortcut { load("cancelHotkeyCode", "cancelHotkeyModifiers", 53, []) }
    static func same(_ a: Shortcut, _ b: Shortcut) -> Bool { ShortcutConflict.matches(code: a.code, modifiers: a.carbonFlags, modifierOnly: a.modifierOnly, otherCode: b.code, otherModifiers: b.carbonFlags) }
}

@MainActor final class HotkeyMonitor {
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var global: Any?
    private var local: Any?
    private var active: Set<UInt32> = []
    private var toggleState = ToggleShortcutState()
    private var recording = false
    private(set) var registrationFailed = false
    var onShortcut: ((Bool) -> Void)?; var onEscape: (() -> Void)?; var onPush: ((Bool) -> Void)?; var onMouse: ((Bool) -> Void)?
    func install() -> Bool {
        stop()
        registrationFailed = false
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID(); guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated { Unmanaged<HotkeyMonitor>.fromOpaque(context).takeUnretainedValue().dispatch(id.id, down) }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
        register(Shortcut.toggle, id: 1)
        if pushAvailable { register(Shortcut.push, id: 2) }
        if recording { register(Shortcut.cancel, id: 3) }
        if AXIsProcessTrusted() {
            local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) }; return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        }
        return !registrationFailed
    }
    private var pushAvailable: Bool { SettingsDefaults.store.bool(forKey: "pushShortcutEnabled") && !Shortcut.same(.toggle, .push) }
    private func register(_ shortcut: Shortcut, id: UInt32) {
        guard !shortcut.modifierOnly else { return }
        var ref: EventHotKeyRef?
        if RegisterEventHotKey(UInt32(shortcut.code), shortcut.carbonFlags, EventHotKeyID(signature: 0x4c545453, id: id), GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs[id] = ref } else { registrationFailed = true }
    }
    func setRecording(_ value: Bool) {
        guard recording != value else { return }; recording = value
        if value { register(Shortcut.cancel, id: 3) } else if let ref = refs.removeValue(forKey: 3) { UnregisterEventHotKey(ref) }
        active.remove(3)
    }
    private func dispatch(_ id: UInt32, _ down: Bool) {
        guard !ShortcutButton.isRecording && !MouseShortcutButton.isRecording else { return }
        if id == 1 { if toggleState.key(down) { onShortcut?(true) }; return }
        if down { toggleState.usedInChord(); guard active.insert(id).inserted else { return } } else { guard active.remove(id) != nil else { return } }
        switch id { case 2: onPush?(down); case 3: if down && recording { onEscape?() }; case 4: onMouse?(down); default: break }
    }
    private func handle(_ event: NSEvent) {
        if event.type == .otherMouseDown || event.type == .otherMouseUp {
            guard event.buttonNumber == (SettingsDefaults.store.object(forKey: "mouseShortcut") as? Int ?? -1) else { return }
            dispatch(4, event.type == .otherMouseDown); return
        }
        if event.type == .keyDown { toggleState.usedInChord(); return }
        let shortcuts: [(UInt32, Shortcut)] = [(1, .toggle)] + (pushAvailable ? [(2, .push)] : []) + (recording ? [(3, .cancel)] : [])
        let masks: [Int: UInt] = [54: 0x10, 55: 0x08, 56: 0x02, 60: 0x04, 58: 0x20, 61: 0x40, 59: 0x01, 62: 0x2000]
        if Shortcut.toggle.modifierOnly && Int(event.keyCode) != Shortcut.toggle.code { toggleState.usedInChord() }
        for (id, shortcut) in shortcuts where shortcut.modifierOnly && shortcut.code == Int(event.keyCode) {
            let down = event.modifierFlags.rawValue & (masks[shortcut.code] ?? 0) != 0
            if id == 1 {
                let activate = toggleState.modifier(down)
                if down && masks.contains(where: { $0.key != shortcut.code && event.modifierFlags.rawValue & $0.value != 0 }) { toggleState.usedInChord() }
                if activate { onShortcut?(true) }
            }
            else { dispatch(id, down) }
        }
    }
    func stop() {
        for ref in refs.values { UnregisterEventHotKey(ref) }; refs.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
        toggleState.reset(); if active.contains(2) { onPush?(false) }; if active.contains(4) { onMouse?(false) }; active.removeAll()
    }
}
