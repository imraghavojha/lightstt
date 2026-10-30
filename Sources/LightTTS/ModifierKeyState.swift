/// Tracks physical Right Option state independently of the aggregate Option flag.
struct ModifierKeyState {
    private(set) var isDown = false
    mutating func update(flags: UInt64) -> Bool? {
        let down = flags & 0x40 != 0 // NX_DEVICERALTKEYMASK
        guard down != isDown else { return nil }
        isDown = down
        return down
    }
    mutating func reset() -> Bool? {
        guard isDown else { return nil }
        isDown = false
        return false
    }
}
