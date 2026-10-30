import Foundation

public enum ShortcutAction: Hashable, Sendable {
    case toggle, pushToTalk, mouse, cancel
}
public enum ShortcutEvent: Equatable, Sendable {
    case toggle, pushDown, pushUp, mouseDown, mouseUp, cancel
}

public enum ShortcutInput: Equatable, Sendable {
    case keyboard(keyCode: UInt16, modifiers: UInt64)
    case mouse(button: Int)
}

public struct ShortcutBinding: Equatable, Sendable {
    public let action: ShortcutAction
    public let input: ShortcutInput
    public let enabled: Bool

    public init(action: ShortcutAction, input: ShortcutInput, enabled: Bool) {
        self.action = action
        self.input = input
        self.enabled = enabled
    }
}

public struct ShortcutBindings: Equatable, Sendable {
    public let bindings: [ShortcutBinding]
    public init(_ bindings: [ShortcutBinding]) {
        self.bindings = bindings
    }
}

public enum ShortcutRegistrationResult: Equatable, Sendable {
    case installed, unavailable
}
public enum ShortcutValidation: Equatable, Sendable {
    case valid
    case invalid(String)
}

public struct ShortcutSnapshot: Equatable, Sendable {
    public let bindings: ShortcutBindings
    public let editing: ShortcutAction?
    public let registration: ShortcutRegistrationResult
    public init(
        bindings: ShortcutBindings, editing: ShortcutAction?,
        registration: ShortcutRegistrationResult
    ) {
        self.bindings = bindings
        self.editing = editing
        self.registration = registration
    }
}

@MainActor
public protocol ShortcutServicing: StateSource where Snapshot == ShortcutSnapshot {
    var onEvent: ((ShortcutEvent) -> Void)? { get set }
    func install() -> Bool
    func stop()
    func setCancellationAvailable(_ available: Bool)
    func beginEditing(_ action: ShortcutAction)
    func save(_ binding: ShortcutBinding) throws
    func cancelEditing()
    func reset(_ action: ShortcutAction) throws
}

@MainActor
public protocol ShortcutMonitoring: AnyObject {
    var onEvent: ((ShortcutEvent) -> Void)? { get set }
    func install(_ bindings: ShortcutBindings) -> ShortcutRegistrationResult
    func stop()
    func setCancellationAvailable(_ available: Bool)
    func validate(_ binding: ShortcutBinding) -> ShortcutValidation
}
