/// Converts physical shortcut events into toggle activations.
public struct ToggleShortcutState {
    private var down = false
    private var chord = false

    public init() {}

    /// Ordinary shortcuts activate on the first key-down, never on repeat or release.
    public mutating func key(_ isDown: Bool) -> Bool {
        if isDown {
            guard !down else { return false }
            down = true
            return true
        }
        down = false
        return false
    }

    /// A clean modifier tap fires immediately on release, when it can be distinguished from a chord.
    public mutating func modifier(_ isDown: Bool) -> Bool {
        if isDown {
            if !down { down = true; chord = false }
            return false
        }
        guard down else { return false }
        down = false
        return !chord
    }

    /// Reconcile a modifier-only shortcut with physical flags, ignoring unrelated flag noise.
    public mutating func flagsChanged(code: Int, shortcutCode: Int, eventFlags: UInt, currentFlags: UInt) -> Bool {
        let masks: [Int: UInt] = [54: 0x10, 55: 0x08, 56: 0x02, 60: 0x04, 58: 0x20, 61: 0x40, 59: 0x01, 62: 0x2000]
        guard let shortcutMask = masks[shortcutCode] else { return false }
        let isTarget = code == shortcutCode
        let eventDown = eventFlags & shortcutMask != 0
        // Process the target's release before reconciliation so a clean tap is not discarded.
        if isTarget && !eventDown { return modifier(false) }
        if currentFlags & shortcutMask == 0 { reset() }
        guard masks[code] != nil else { return false }
        if !isTarget { usedInChord(); return false }
        guard currentFlags & shortcutMask != 0 else { return false }
        let activate = modifier(true)
        if masks.contains(where: { $0.key != shortcutCode && eventFlags & $0.value != 0 }) { usedInChord() }
        return activate
    }

    public mutating func usedInChord() { if down { chord = true } }
    public mutating func reset() { down = false; chord = false }
}
