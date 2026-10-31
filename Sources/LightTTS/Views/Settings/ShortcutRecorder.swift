import AppKit
import SwiftUI
import Carbon

enum SettingsDefaults {
    static var store: UserDefaults { CommandLine.arguments.contains("--ui-fixture") ? (UserDefaults(suiteName: "com.lighttts.ui-fixture") ?? .standard) : .standard }
}

struct ShortcutRecorder: NSViewRepresentable {
    let codeKey: String
    let modifiersKey: String?
    let fallbackCode: Int
    var enabledKey: String? = nil
    func makeNSView(context: Context) -> ShortcutButton { ShortcutButton(codeKey: codeKey, modifiersKey: modifiersKey, fallbackCode: fallbackCode, enabledKey: enabledKey) }
    func updateNSView(_ view: ShortcutButton, context: Context) { view.refresh() }
}
final class ShortcutButton: NSButton {
    static var isRecording = false
    let codeKey: String; let modifiersKey: String?; let fallbackCode: Int; let enabledKey: String?
    private var recording = false; private var modifierCandidate: Int?
    private var keycaps: [String] = []
    init(codeKey: String, modifiersKey: String?, fallbackCode: Int, enabledKey: String?) {
        self.codeKey = codeKey; self.modifiersKey = modifiersKey; self.fallbackCode = fallbackCode; self.enabledKey = enabledKey
        super.init(frame: .zero); isBordered = false; controlSize = .small; font = .systemFont(ofSize: 11, weight: .medium); target = self; action = #selector(begin)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsChanged), name: .shortcutsChanged, object: nil)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func shortcutsChanged() { refresh() }
    private var actionName: String { codeKey == "hotkeyCode" ? "Toggle Recording" : codeKey == "pushHotkeyCode" ? "Push to Talk" : "Cancel Recording" }
    @objc private func begin() { recording = true; Self.isRecording = true; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); modifierCandidate = nil; setDisplay("Press shortcut… Esc cancels"); setAccessibilityLabel("Recording \(actionName) shortcut. Press a shortcut, or Escape to cancel."); window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        modifierCandidate = nil
        save(Shortcut(code: Int(event.keyCode), flags: event.modifierFlags.intersection([.option, .command, .control, .shift])))
    }
    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
        let code = Int(event.keyCode), flags = event.modifierFlags.intersection([.option, .command, .control, .shift])
        if flags.isEmpty, modifierCandidate == code { save(Shortcut(code: code, flags: [])) }
        else if modifierCandidate == nil { modifierCandidate = code }
    }
    private func save(_ candidate: Shortcut) {
        if let warning = Self.validate(candidate, codeKey: codeKey) { setDisplay(warning); return }
        SettingsDefaults.store.set(candidate.code, forKey: codeKey)
        if let modifiersKey { SettingsDefaults.store.set(Int(candidate.flags.rawValue), forKey: modifiersKey) }
        if codeKey == "hotkeyCode" { SettingsDefaults.store.set(false, forKey: "rightOption") }
        if let enabledKey { SettingsDefaults.store.set(true, forKey: enabledKey) }
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil); finish()
    }
    private static func validate(_ candidate: Shortcut, codeKey: String) -> String? {
        let others: [(String, Shortcut, Bool)] = [("hotkeyCode", .toggle, true), ("pushHotkeyCode", .push, SettingsDefaults.store.bool(forKey: "pushShortcutEnabled")), ("cancelHotkeyCode", .cancel, true)]
        if let conflict = others.first(where: { $0.0 != codeKey && $0.2 && Shortcut.same($0.1, candidate) }) { return "Used by " + (conflict.0 == "hotkeyCode" ? "Toggle Recording" : conflict.0 == "pushHotkeyCode" ? "Push to Talk" : "Cancel Recording") + "; try another" }
        if !candidate.modifierOnly {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(candidate.code), candidate.carbonFlags, EventHotKeyID(signature: 0x4c545453, id: 99), GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            if status != noErr { return status == eventHotKeyExistsErr ? "Shortcut in use; try another" : "Shortcut unavailable; try another" }
        }
        return nil
    }
    static func reset(codeKey: String, modifiersKey: String?) {
        let candidate = codeKey == "hotkeyCode" ? Shortcut(code: 49, flags: .option) : Shortcut(code: 53, flags: [])
        // Temporarily release our registrations, just as when recording a shortcut.
        isRecording = true; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil)
        let warning = validate(candidate, codeKey: codeKey)
        if warning == nil {
            SettingsDefaults.store.removeObject(forKey: codeKey)
            if let modifiersKey { SettingsDefaults.store.removeObject(forKey: modifiersKey) }
            if codeKey == "hotkeyCode" { SettingsDefaults.store.set(false, forKey: "rightOption") }
        }
        isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil)
        if let warning { let alert = NSAlert(); alert.messageText = warning; alert.informativeText = "Choose another shortcut before resetting."; alert.runModal() }
    }
    private func finish() { recording = false; Self.isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); refresh(); window?.makeFirstResponder(nil) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && recording { finish() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func resignFirstResponder() -> Bool { let wasRecording = recording; recording = false; Self.isRecording = false; if wasRecording { NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil) }; refresh(); return super.resignFirstResponder() }
    func refresh() {
        guard !recording else { return }
        let d = SettingsDefaults.store
        toolTip = "Edit \(actionName) shortcut. Press Escape to cancel."
        if let enabledKey, !d.bool(forKey: enabledKey) { setDisplay("Disabled — record shortcut"); setAccessibilityLabel("\(actionName) disabled. Record shortcut"); return }
        let shortcut = codeKey == "hotkeyCode" ? Shortcut.toggle : (codeKey == "pushHotkeyCode" ? Shortcut.push : Shortcut.cancel)
        setAccessibilityLabel("Edit \(actionName) shortcut, \(Self.displayName(shortcut))")
        let flags = shortcut.flags
        let prefix = shortcut.modifierOnly ? "" : (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        let parts = prefix.map { String($0) } + [Self.keyName(shortcut.code)]
        setDisplay(parts.joined(separator: " "), keycaps: parts)
    }
    private func setDisplay(_ text: String, keycaps: [String] = []) {
        title = text; self.keycaps = keycaps
        invalidateIntrinsicContentSize(); needsDisplay = true
    }
    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
    }
    private func capWidth(_ text: String) -> CGFloat { max(18, ceil((text as NSString).size(withAttributes: textAttributes).width) + 10) }
    override var intrinsicContentSize: NSSize {
        let width = keycaps.isEmpty ? ceil((title as NSString).size(withAttributes: textAttributes).width) + 4 : keycaps.reduce(CGFloat(0)) { $0 + capWidth($1) } + CGFloat(max(0, keycaps.count - 1) * 4)
        return NSSize(width: width, height: 28)
    }
    override func draw(_ dirtyRect: NSRect) {
        if keycaps.isEmpty {
            let size = (title as NSString).size(withAttributes: textAttributes)
            (title as NSString).draw(at: NSPoint(x: 2, y: (bounds.height - size.height) / 2), withAttributes: textAttributes)
        } else {
            var x: CGFloat = 0
            for cap in keycaps {
                let width = capWidth(cap), rect = NSRect(x: x, y: (bounds.height - 18) / 2, width: width, height: 18)
                NSColor.labelColor.withAlphaComponent(0.16).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
                let size = (cap as NSString).size(withAttributes: textAttributes)
                (cap as NSString).draw(at: NSPoint(x: x + (width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: textAttributes)
                x += width + 4
            }
        }
    }
    static func displayName(_ shortcut: Shortcut) -> String {
        let flags = shortcut.flags
        let prefix = shortcut.modifierOnly ? "" : (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        return prefix + keyName(shortcut.code)
    }
    private static func keyName(_ code: Int) -> String {
        let names = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"esc",54:"Right ⌘",55:"⌘",56:"⇧",57:"Caps Lock",58:"⌥",59:"⌃",60:"Right ⇧",61:"Right ⌥",62:"Right ⌃",63:"fn",65:"Keypad .",67:"Keypad *",69:"Keypad +",71:"Clear",75:"Keypad /",76:"⌤",78:"Keypad −",81:"Keypad =",82:"Keypad 0",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",105:"F13",106:"F16",107:"F14",109:"F10",111:"F12",113:"F15",114:"Help",115:"Home",116:"Page Up",117:"⌦",118:"F4",119:"End",120:"F2",121:"Page Down",122:"F1",123:"←",124:"→",125:"↓",126:"↑",64:"F17",79:"F18",80:"F19",90:"F20"]
        return names[code] ?? "Key \(code)"
    }
}

struct MouseShortcutRecorder: NSViewRepresentable {
    func makeNSView(context: Context) -> MouseShortcutButton { MouseShortcutButton() }
    func updateNSView(_ view: MouseShortcutButton, context: Context) { view.refresh() }
}
final class MouseShortcutButton: NSButton {
    static var isRecording = false
    override init(frame: NSRect) {
        super.init(frame: frame); isBordered = false; target = self; action = #selector(begin)
        NotificationCenter.default.addObserver(self, selector: #selector(shortcutsChanged), name: .shortcutsChanged, object: nil)
        refresh()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func shortcutsChanged() { refresh() }
    @objc private func begin() { Self.isRecording = true; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); title = "Click a mouse button; Esc cancels"; setAccessibilityLabel("Recording mouse shortcut. Click a mouse button, or press Escape to cancel."); invalidateIntrinsicContentSize(); window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if Self.isRecording && event.keyCode == 53 { window?.makeFirstResponder(nil); return }
        super.keyDown(with: event)
    }
    override func otherMouseDown(with event: NSEvent) { guard Self.isRecording else { super.otherMouseDown(with: event); return }; SettingsDefaults.store.set(event.buttonNumber, forKey: "mouseShortcut"); Self.isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); refresh(); window?.makeFirstResponder(nil) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && Self.isRecording { Self.isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func resignFirstResponder() -> Bool { let wasRecording = Self.isRecording; Self.isRecording = false; if wasRecording { NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil) }; refresh(); return super.resignFirstResponder() }
    override var intrinsicContentSize: NSSize { NSSize(width: max(90, ceil((title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 4), height: 28) }
    func refresh() { guard !Self.isRecording else { return }; let value = SettingsDefaults.store.object(forKey: "mouseShortcut") as? Int ?? -1; title = value < 0 ? "Record shortcut" : "Mouse \(value + 1)"; setAccessibilityLabel("Edit mouse shortcut, \(value < 0 ? "disabled" : "Mouse \(value + 1)")"); toolTip = "Edit mouse shortcut. Press Escape to cancel."; font = .systemFont(ofSize: 12, weight: .medium); contentTintColor = .secondaryLabelColor; invalidateIntrinsicContentSize() }
}
