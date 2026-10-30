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
    init(codeKey: String, modifiersKey: String?, fallbackCode: Int, enabledKey: String?) {
        self.codeKey = codeKey; self.modifiersKey = modifiersKey; self.fallbackCode = fallbackCode; self.enabledKey = enabledKey
        super.init(frame: .zero); bezelStyle = .rounded; controlSize = .small; font = .systemFont(ofSize: 11, weight: .medium); target = self; action = #selector(begin); refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func begin() { recording = true; Self.isRecording = true; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); modifierCandidate = nil; title = "Press shortcut…"; window?.makeFirstResponder(self) }
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
        let others: [(String, Shortcut, Bool)] = [("hotkeyCode", .toggle, true), ("pushHotkeyCode", .push, SettingsDefaults.store.bool(forKey: "pushShortcutEnabled")), ("cancelHotkeyCode", .cancel, true)]
        if others.contains(where: { $0.0 != codeKey && $0.2 && Shortcut.same($0.1, candidate) }) { title = "Already used by LightTTS"; return }
        if !candidate.modifierOnly {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(candidate.code), candidate.carbonFlags, EventHotKeyID(signature: 0x4c545453, id: 99), GetApplicationEventTarget(), 0, &ref)
            if let ref { UnregisterEventHotKey(ref) }
            if status != noErr { title = status == eventHotKeyExistsErr ? "Shortcut already in use" : "Shortcut unavailable"; return }
        }
        SettingsDefaults.store.set(candidate.code, forKey: codeKey)
        if let modifiersKey { SettingsDefaults.store.set(Int(candidate.flags.rawValue), forKey: modifiersKey) }
        if codeKey == "hotkeyCode" { SettingsDefaults.store.set(false, forKey: "rightOption") }
        if let enabledKey { SettingsDefaults.store.set(true, forKey: enabledKey) }
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil); finish()
    }
    private func finish() { recording = false; Self.isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); refresh(); window?.makeFirstResponder(nil) }
    override func resignFirstResponder() -> Bool { let wasRecording = recording; recording = false; Self.isRecording = false; if wasRecording { NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil) }; refresh(); return super.resignFirstResponder() }
    func refresh() {
        guard !recording else { return }
        let d = SettingsDefaults.store
        if let enabledKey, !d.bool(forKey: enabledKey) { title = "Record shortcut"; return }
        let shortcut = codeKey == "hotkeyCode" ? Shortcut.toggle : (codeKey == "pushHotkeyCode" ? Shortcut.push : Shortcut.cancel)
        let flags = shortcut.flags
        let prefix = shortcut.modifierOnly ? "" : (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        title = prefix + (prefix.isEmpty ? "" : " ") + Self.keyName(shortcut.code)
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
        super.init(frame: frame); isBordered = false; target = self; action = #selector(begin); refresh()
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func begin() { Self.isRecording = true; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); title = "Click a mouse button"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func otherMouseDown(with event: NSEvent) { guard Self.isRecording else { super.otherMouseDown(with: event); return }; SettingsDefaults.store.set(event.buttonNumber, forKey: "mouseShortcut"); Self.isRecording = false; NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil); refresh(); window?.makeFirstResponder(nil) }
    override func resignFirstResponder() -> Bool { let wasRecording = Self.isRecording; Self.isRecording = false; if wasRecording { NotificationCenter.default.post(name: .shortcutCaptureChanged, object: nil) }; refresh(); return super.resignFirstResponder() }
    func refresh() { guard !Self.isRecording else { return }; let value = SettingsDefaults.store.object(forKey: "mouseShortcut") as? Int ?? -1; title = value < 0 ? "Record shortcut" : "Mouse \(value + 1)"; font = .systemFont(ofSize: 12, weight: .medium); contentTintColor = .secondaryLabelColor }
}
