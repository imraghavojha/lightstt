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
    // Optional injected configuration is used by the runtime bridge; the legacy app
    // continues to read its existing settings until it is migrated.
    var configuredShortcuts: [UInt32: Shortcut]?
    var configuredMouseButton: Int?
    var captureSuspended: (() -> Bool)?
    private var toggleShortcut: Shortcut { configuredShortcuts?[1] ?? .toggle }
    private var pushShortcut: Shortcut { configuredShortcuts?[2] ?? .push }
    private var cancelShortcut: Shortcut { configuredShortcuts?[3] ?? .cancel }
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var global: Any?
    private var local: Any?
    private var active: Set<UInt32> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var unlockObserver: NSObjectProtocol?
    private var toggleState = ToggleShortcutState()
    private var cancelState = CancelRegistrationState()
    private var recording: Bool { cancelState.recording }
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
        cancelState.setInstalled(true)
        register(toggleShortcut, id: 1)
        if pushAvailable { register(pushShortcut, id: 2) }
        if AXIsProcessTrusted() {
            local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event, currentFlags: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue)) }; return event
            }
            global = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                let currentFlags = UInt(CGEventSource.flagsState(.combinedSessionState).rawValue)
                Task { @MainActor in self?.handle(event, currentFlags: currentFlags) }
            }
        }
        if cancelState.shouldRegister { registerCancel() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidBecomeActiveNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resynchronize() }
            })
        }
        unlockObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resynchronize() }
        }
        return !registrationFailed
    }
    private var pushAvailable: Bool { (configuredShortcuts == nil ? SettingsDefaults.store.bool(forKey: "pushShortcutEnabled") : configuredShortcuts?[2] != nil) && !Shortcut.same(toggleShortcut, pushShortcut) }
    private func register(_ shortcut: Shortcut, id: UInt32) {
        guard !shortcut.modifierOnly else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.code), shortcut.carbonFlags, EventHotKeyID(signature: 0x4c545453, id: id), GetApplicationEventTarget(), 0, &ref)
        traceCancel("register id=\(id) code=\(shortcut.code) modifiers=\(shortcut.carbonFlags) status=\(status)")
        if status == noErr, let ref { refs[id] = ref } else { registrationFailed = true }
    }
    func setRecording(_ value: Bool) {
        guard recording != value else { return }; cancelState.setRecording(value)
        if cancelState.shouldRegister { registerCancel() } else if let ref = refs.removeValue(forKey: 3) { UnregisterEventHotKey(ref); traceCancel("unregistered") } else { traceCancel("inactive") }
        active.remove(3)
    }
    private func traceCancel(_ status: String) {
        if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { NSLog("LIGHTTTS_TRACE cancel %@", status) }
    }
    private func registerCancel() {
        let shortcut = cancelShortcut
        if shortcut.modifierOnly { traceCancel("modifier cancel uses flags monitor") }
        else { register(shortcut, id: 3) }
    }
    private func dispatch(_ id: UInt32, _ down: Bool) {
        traceCancel("dispatch id=\(id) down=\(down) recording=\(recording)")
        guard !(captureSuspended?() ?? (ShortcutButton.isRecording || MouseShortcutButton.isRecording)) else { return }
        if id == 1 { if toggleState.key(down) { onShortcut?(true) }; return }
        if down { toggleState.usedInChord(); guard active.insert(id).inserted else { return } } else { guard active.remove(id) != nil else { return } }
        switch id { case 2: onPush?(down); case 3: if down && recording { onEscape?() }; case 4: onMouse?(down); default: break }
    }
    private func handle(_ event: NSEvent, currentFlags: UInt) {
        if event.type == .otherMouseDown || event.type == .otherMouseUp {
            guard event.buttonNumber == (configuredMouseButton ?? (SettingsDefaults.store.object(forKey: "mouseShortcut") as? Int ?? -1)) else { return }
            dispatch(4, event.type == .otherMouseDown); return
        }
        if event.type == .keyDown {
            toggleState.usedInChord()
            return
        }
        let shortcuts: [(UInt32, Shortcut)] = [(1, toggleShortcut)] + (pushAvailable ? [(UInt32(2), pushShortcut)] : []) + (recording ? [(UInt32(3), cancelShortcut)] : [])
        let masks: [Int: UInt] = [54: 0x10, 55: 0x08, 56: 0x02, 60: 0x04, 58: 0x20, 61: 0x40, 59: 0x01, 62: 0x2000]
        if toggleShortcut.modifierOnly {
            if toggleState.flagsChanged(code: Int(event.keyCode), shortcutCode: toggleShortcut.code, eventFlags: event.modifierFlags.rawValue, currentFlags: currentFlags) { onShortcut?(true) }
        }
        // Recover a missed modifier push-to-talk release even when this event is unrelated.
        if pushAvailable && pushShortcut.modifierOnly && Int(event.keyCode) != pushShortcut.code && currentFlags & (masks[pushShortcut.code] ?? 0) == 0 && active.contains(2) { dispatch(2, false) }
        for (id, shortcut) in shortcuts where id != 1 && shortcut.modifierOnly && shortcut.code == Int(event.keyCode) {
            let down = event.modifierFlags.rawValue & (masks[shortcut.code] ?? 0) != 0
            dispatch(id, down)
        }
    }
    private func resynchronize() {
        toggleState.reset()
        if active.contains(2) { onPush?(false) }
        if active.contains(4) { onMouse?(false) }
        active.removeAll()
    }
    func stop() {
        cancelState.setInstalled(false)
        traceCancel("monitor stopped")
        for ref in refs.values { UnregisterEventHotKey(ref) }; refs.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; workspaceObservers.removeAll()
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }; unlockObserver = nil
        resynchronize()
    }
}
