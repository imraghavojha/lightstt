import Foundation
import LightTTSRuntime
import XCTest

@MainActor
private final class FakeShortcutMonitor: ShortcutMonitoring {
    var onEvent: ((ShortcutEvent) -> Void)?
    var installs = 0
    var stops = 0
    var cancellation = false
    var validation: ShortcutValidation = .valid
    var result: ShortcutRegistrationResult = .installed
    func install(_ bindings: ShortcutBindings) -> ShortcutRegistrationResult {
        installs += 1
        return result
    }
    func stop() { stops += 1 }
    func setCancellationAvailable(_ available: Bool) { cancellation = available }
    func validate(_ binding: ShortcutBinding) -> ShortcutValidation { validation }
}

final class ShortcutServiceTests: XCTestCase {
    @MainActor
    func testEditingPersistenceResetAndCancelAvailability() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ShortcutPreferences(defaults: defaults)
        let monitor = FakeShortcutMonitor()
        let service = ShortcutService(preferences: preferences, monitor: monitor)
        var events: [ShortcutEvent] = []
        service.onEvent = { events.append($0) }
        XCTAssertTrue(service.install())
        monitor.onEvent?(.cancel)
        service.setCancellationAvailable(true)
        monitor.onEvent?(.cancel)
        XCTAssertEqual(events, [.cancel])
        service.beginEditing(.toggle)
        monitor.onEvent?(.toggle)
        XCTAssertEqual(events, [.cancel])
        let binding = ShortcutBinding(
            action: .toggle, input: .keyboard(keyCode: 61, modifiers: 0), enabled: true)
        try service.save(binding)
        XCTAssertEqual(preferences.bindings().bindings.first, binding)
        XCTAssertEqual(defaults.integer(forKey: "hotkeyCode"), 61)
        XCTAssertEqual(monitor.installs, 2)
        try service.reset(.toggle)
        XCTAssertEqual(
            preferences.bindings().bindings.first, ShortcutPreferences.defaultBinding(.toggle))
        XCTAssertFalse(defaults.bool(forKey: "rightOption"))
    }

    @MainActor
    func testConflictsAndUnavailableRegistration() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let monitor = FakeShortcutMonitor()
        let service = ShortcutService(
            preferences: ShortcutPreferences(defaults: defaults), monitor: monitor)
        monitor.result = .unavailable
        XCTAssertFalse(service.install())
        service.beginEditing(.pushToTalk)
        let duplicate = ShortcutBinding(
            action: .pushToTalk, input: .keyboard(keyCode: 49, modifiers: 1 << 19), enabled: true)
        XCTAssertThrowsError(try service.save(duplicate))
        monitor.validation = .invalid("Shortcut already in use")
        let candidate = ShortcutBinding(
            action: .pushToTalk, input: .keyboard(keyCode: 42, modifiers: 0), enabled: true)
        XCTAssertThrowsError(try service.save(candidate))
        XCTAssertEqual(service.snapshot.editing, .pushToTalk)
        service.cancelEditing()
    }
}
