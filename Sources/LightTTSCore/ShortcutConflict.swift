public enum ShortcutConflict {
    public static func matches(code: Int, modifiers: UInt32, modifierOnly: Bool, otherCode: Int, otherModifiers: UInt32) -> Bool {
        code == otherCode && (modifierOnly || modifiers == otherModifiers)
    }
}
