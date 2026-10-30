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

    /// Modifier-only shortcuts activate on release only if no chord was used.
    public mutating func modifier(_ isDown: Bool) -> Bool {
        if isDown {
            if !down { down = true; chord = false }
            return false
        }
        guard down else { return false }
        down = false
        return !chord
    }

    public mutating func usedInChord() { if down { chord = true } }
    public mutating func reset() { down = false; chord = false }
}
