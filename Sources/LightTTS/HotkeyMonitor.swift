import AppKit
import ApplicationServices

/// An active session event tap consumes the shortcut before it reaches the focused app.
@MainActor final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activeKey = false
    var onShortcut: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    func install() -> Bool {
        stop()
        let accessibility = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS test: accessibility=\(accessibility) input=\(input)\n", stderr) }
        guard accessibility, input else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(info).takeUnretainedValue()
            return MainActor.assumeIsolated { monitor.handle(type, event) ? nil : Unmanaged.passUnretained(event) }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS test: event tap creation failed\n", stderr) }; return false }
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS test: event tap active\n", stderr) }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0); self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if activeKey { activeKey = false; DispatchQueue.main.async { self.onShortcut?(false) } }; if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown && code == 53 { DispatchQueue.main.async { self.onEscape?() }; return false }
        let right = UserDefaults.standard.bool(forKey: "rightOption")
        if right {
            guard type == .flagsChanged && code == 61 else { return false }
            activeKey = !activeKey; let down = activeKey; DispatchQueue.main.async { self.onShortcut?(down) }; return false
        }
        let key = UserDefaults.standard.object(forKey: "hotkeyCode") as? Int ?? 49
        guard code == key, type == .keyDown || type == .keyUp else { return false }
        if type == .keyDown {
            guard activeKey || event.flags.contains(.maskAlternate) else { return false }
            if !activeKey { activeKey = true; DispatchQueue.main.async { self.onShortcut?(true) } }
            return true
        }
        guard activeKey else { return false }
        activeKey = false; DispatchQueue.main.async { self.onShortcut?(false) }; return true
    }
    func stop() { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; if let tap { CFMachPortInvalidate(tap) }; source = nil; tap = nil; activeKey = false }
}
