import AppKit
import ApplicationServices
import AVFoundation

/// An active session event tap consumes the shortcut before it reaches the focused app.
@MainActor final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var activeKey = false
    private var rightOption = ModifierKeyState()
    private var pushActive = false
    private var mouseActive = false
    var onShortcut: ((Bool) -> Void)?
    var onEscape: (() -> Void)?
    var onPush: ((Bool) -> Void)?
    var onMouse: ((Bool) -> Void)?
    func install() -> Bool {
        stop()
        let accessibility = AXIsProcessTrusted(), input = CGPreflightListenEventAccess()
        if ProcessInfo.processInfo.environment["LIGHTTTS_TEST_TRACE"] == "1" { fputs("LightTTS test: accessibility=\(accessibility) input=\(input) microphone=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)\n", stderr) }
        guard accessibility, input else { return false }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)
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
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { if rightOption.reset() != nil || activeKey { activeKey = false; DispatchQueue.main.async { self.onShortcut?(false) } }; if pushActive { pushActive = false; DispatchQueue.main.async { self.onPush?(false) } }; if mouseActive { mouseActive = false; DispatchQueue.main.async { self.onMouse?(false) } }; if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false }
        if ShortcutButton.isRecording || MouseShortcutButton.isRecording { return false }
        if type == .otherMouseDown || type == .otherMouseUp {
            let selected = UserDefaults.standard.object(forKey: "mouseShortcut") as? Int ?? -1
            guard selected >= 0, event.getIntegerValueField(.mouseEventButtonNumber) == selected else { return false }
            let down = type == .otherMouseDown
            if down != mouseActive { mouseActive = down; DispatchQueue.main.async { self.onMouse?(down) } }
            return true
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand])
        if type == .keyDown && flags.isEmpty && code == (UserDefaults.standard.object(forKey: "cancelHotkeyCode") as? Int ?? 53) { DispatchQueue.main.async { self.onEscape?() }; return false }
        if UserDefaults.standard.bool(forKey: "pushShortcutEnabled"), code == (UserDefaults.standard.object(forKey: "pushHotkeyCode") as? Int ?? 49), type == .keyDown || type == .keyUp {
            let required = CGEventFlags(rawValue: UInt64(UserDefaults.standard.object(forKey: "pushHotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.option.union(.shift).rawValue)))
            if type == .keyDown && flags == required { if !pushActive { pushActive = true; DispatchQueue.main.async { self.onPush?(true) } }; return true }
            if type == .keyUp && pushActive { pushActive = false; DispatchQueue.main.async { self.onPush?(false) }; return true }
        }
        let right = UserDefaults.standard.bool(forKey: "rightOption")
        if right {
            guard type == .flagsChanged && code == 61 else { return false }
            guard let down = rightOption.update(flags: event.flags.rawValue) else { return false }
            DispatchQueue.main.async { self.onShortcut?(down) }; return false
        }
        let key = UserDefaults.standard.object(forKey: "hotkeyCode") as? Int ?? 49
        guard code == key, type == .keyDown || type == .keyUp else { return false }
        let required = CGEventFlags(rawValue: UInt64(UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? Int(NSEvent.ModifierFlags.option.rawValue)))
        if type == .keyDown {
            guard activeKey || flags == required else { return false }
            if !activeKey { activeKey = true; DispatchQueue.main.async { self.onShortcut?(true) } }
            return true
        }
        guard activeKey else { return false }
        activeKey = false; DispatchQueue.main.async { self.onShortcut?(false) }; return true
    }
    func stop() { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; if let tap { CFMachPortInvalidate(tap) }; source = nil; tap = nil; if rightOption.reset() != nil || activeKey { activeKey = false; DispatchQueue.main.async { self.onShortcut?(false) } }; if pushActive { pushActive = false; DispatchQueue.main.async { self.onPush?(false) } }; if mouseActive { mouseActive = false; DispatchQueue.main.async { self.onMouse?(false) } } }
}
