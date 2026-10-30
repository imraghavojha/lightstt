import AppKit
import SwiftUI

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
    let codeKey: String
    let modifiersKey: String?
    let fallbackCode: Int
    let enabledKey: String?
    private var recording = false
    init(codeKey: String, modifiersKey: String?, fallbackCode: Int, enabledKey: String?) {
        self.codeKey = codeKey; self.modifiersKey = modifiersKey; self.fallbackCode = fallbackCode; self.enabledKey = enabledKey
        super.init(frame: .zero); bezelStyle = .rounded; controlSize = .small; font = .systemFont(ofSize: 11, weight: .medium); target = self; action = #selector(begin); refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func begin() { recording = true; Self.isRecording = true; title = "Press shortcut…"; window?.makeFirstResponder(self) }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let flags = event.modifierFlags.intersection([.option, .command, .control, .shift])
        if modifiersKey != nil && flags.isEmpty { NSSound.beep(); return }
        UserDefaults.standard.set(Int(event.keyCode), forKey: codeKey)
        if let enabledKey { UserDefaults.standard.set(true, forKey: enabledKey) }
        if let modifiersKey { UserDefaults.standard.set(Int(flags.rawValue), forKey: modifiersKey); UserDefaults.standard.set(false, forKey: "rightOption") }
        recording = false; Self.isRecording = false; refresh(); window?.makeFirstResponder(nil)
    }
    override func resignFirstResponder() -> Bool { recording = false; Self.isRecording = false; refresh(); return super.resignFirstResponder() }
    func refresh() {
        guard !recording else { return }
        let defaults = UserDefaults.standard
        if let enabledKey, !defaults.bool(forKey: enabledKey) { title = "Record…"; return }
        let code = defaults.object(forKey: codeKey) as? Int ?? fallbackCode
        let raw = modifiersKey.flatMap { defaults.object(forKey: $0) as? Int } ?? (modifiersKey == nil ? 0 : Int(NSEvent.ModifierFlags.option.rawValue))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(raw))
        let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
        let key = code == 49 ? "Space" : code == 53 ? "esc" : (keyName(code) ?? "Key \(code)")
        title = prefix + " " + key
    }
    private func keyName(_ code: Int) -> String? {
        let names = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M"]
        return names[code]
    }
}
