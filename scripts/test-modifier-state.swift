// swiftc Sources/LightTTS/ModifierKeyState.swift scripts/test-modifier-state.swift -o /tmp/lighttts-modifier-test && /tmp/lighttts-modifier-test
@main struct TestModifierState {
    static func main() {
        var state = ModifierKeyState()
        precondition(state.update(flags: 0x40) == true)
        precondition(state.reset() == false)
        precondition(state.update(flags: 0) == nil)
        precondition(state.update(flags: 0x40) == true)
        precondition(state.update(flags: 0x20) == false)
        precondition(state.update(flags: 0x20) == nil)
        print("Right Option recovery replay passed")
    }
}
