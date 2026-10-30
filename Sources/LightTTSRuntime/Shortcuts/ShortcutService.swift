import Foundation

public struct ShortcutError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

@MainActor
public final class ShortcutService: ShortcutServicing {
    private let preferences: ShortcutPreferences
    private let monitor: any ShortcutMonitoring
    private var running = false
    private var cancellationAvailable = false
    private var observers: [UUID: AsyncStream<ShortcutSnapshot>.Continuation] = [:]
    public var onEvent: ((ShortcutEvent) -> Void)?
    public private(set) var snapshot: ShortcutSnapshot

    public init(preferences: ShortcutPreferences, monitor: any ShortcutMonitoring) {
        self.preferences = preferences
        self.monitor = monitor
        snapshot = ShortcutSnapshot(
            bindings: preferences.bindings(), editing: nil, registration: .unavailable)
        monitor.onEvent = { [weak self] event in
            guard let self, self.running, self.snapshot.editing == nil else { return }
            if event == .cancel && !self.cancellationAvailable { return }
            self.onEvent?(event)
        }
    }

    public func snapshots() -> AsyncStream<ShortcutSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers.removeValue(forKey: id) }
            }
        }
    }

    @discardableResult public func install() -> Bool {
        running = true
        guard snapshot.editing == nil else { return false }
        return register() == .installed
    }

    public func stop() {
        running = false
        monitor.stop()
        update(editing: nil, registration: .unavailable)
    }

    public func setCancellationAvailable(_ available: Bool) {
        cancellationAvailable = available
        monitor.setCancellationAvailable(available)
    }

    public func beginEditing(_ action: ShortcutAction) {
        monitor.stop()
        update(editing: action, registration: .unavailable)
    }

    public func cancelEditing() {
        update(editing: nil, registration: .unavailable)
        if running { _ = register() }
    }

    public func save(_ binding: ShortcutBinding) throws {
        let wasEditing = snapshot.editing
        if wasEditing == nil { beginEditing(binding.action) }
        do {
            try validate(preferences.effectiveBinding(binding))
            preferences.save(binding)
            cancelEditing()
        } catch {
            if wasEditing == nil { cancelEditing() }
            throw error
        }
    }

    public func reset(_ action: ShortcutAction) throws {
        let wasEditing = snapshot.editing
        if wasEditing == nil { beginEditing(action) }
        do {
            try validate(ShortcutPreferences.defaultBinding(action))
            preferences.reset(action)
            cancelEditing()
        } catch {
            if wasEditing == nil { cancelEditing() }
            throw error
        }
    }

    private func validate(_ binding: ShortcutBinding) throws {
        if !binding.enabled && (binding.action == .toggle || binding.action == .cancel) {
            throw ShortcutError("This shortcut cannot be disabled")
        }
        switch (binding.action, binding.input) {
        case (.mouse, .mouse(let button)) where !binding.enabled || button >= 0: break
        case (.toggle, .keyboard), (.pushToTalk, .keyboard), (.cancel, .keyboard): break
        default: throw ShortcutError("Invalid shortcut")
        }
        if binding.enabled {
            for other in preferences.bindings().bindings
            where other.action != binding.action && other.enabled {
                if conflicts(binding.input, other.input) {
                    throw ShortcutError("Already used by LightTTS")
                }
            }
            if case .invalid(let message) = monitor.validate(binding) {
                throw ShortcutError(message)
            }
        }
    }

    private func conflicts(_ a: ShortcutInput, _ b: ShortcutInput) -> Bool {
        switch (a, b) {
        case (.keyboard(let code, let flags), .keyboard(let otherCode, let otherFlags)):
            let modifiers: Set<UInt16> = [54, 55, 56, 60, 58, 61, 59, 62]
            let mask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
            return code == otherCode
                && (modifiers.contains(code) || flags & mask == otherFlags & mask)
        case (.mouse(let button), .mouse(let other)): return button == other
        default: return false
        }
    }

    private func register() -> ShortcutRegistrationResult {
        let result = monitor.install(preferences.bindings())
        monitor.setCancellationAvailable(cancellationAvailable)
        update(editing: nil, registration: result)
        return result
    }

    private func update(editing: ShortcutAction?, registration: ShortcutRegistrationResult) {
        snapshot = ShortcutSnapshot(
            bindings: preferences.bindings(), editing: editing, registration: registration)
        for continuation in observers.values { continuation.yield(snapshot) }
    }
}
