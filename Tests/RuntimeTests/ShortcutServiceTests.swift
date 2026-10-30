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
    var releaseOnStop = false
    var validated: [ShortcutBinding] = []
    func install(_ bindings: ShortcutBindings) -> ShortcutRegistrationResult {
        installs += 1
        return result
    }
    func stop() {
        stops += 1
        if releaseOnStop { onEvent?(.pushUp) }
    }
    func setCancellationAvailable(_ available: Bool) { cancellation = available }
    func validate(_ binding: ShortcutBinding) -> ShortcutValidation {
        validated.append(binding)
        return validation
    }
}

@MainActor
private final class EditingRecording: RecordingControlling {
    var snapshot = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    var stops = 0
    func snapshots() -> AsyncStream<RecordingSnapshot> { AsyncStream { $0.finish() } }
    func start(trigger: RecordingTrigger) {
        snapshot = RecordingSnapshot(
            phase: .recording, sessionID: SessionID(generation: 1), startDate: nil, message: nil)
    }
    func stop() {
        stops += 1
        snapshot = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    }
    func cancel() {}
    func dismissResult() {}
    func beginShutdown() {}
    func finishShutdown() async {}
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
    @MainActor
    func testEditingFinishesActivePushSession() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let monitor = FakeShortcutMonitor()
        let service = ShortcutService(
            preferences: ShortcutPreferences(defaults: defaults), monitor: monitor)
        let recording = EditingRecording()
        let router = RecordingTriggerRouter(recording: recording, scheduler: ManualScheduler())
        service.onEvent = { router.handle($0) }
        XCTAssertTrue(service.install())
        monitor.onEvent?(.pushDown)
        XCTAssertEqual(recording.snapshot.phase, .recording)
        monitor.releaseOnStop = true
        service.beginEditing(.toggle)
        XCTAssertEqual(recording.stops, 1)
        XCTAssertEqual(recording.snapshot.phase, .idle)
        service.cancelEditing()
        XCTAssertNil(service.snapshot.editing)
        XCTAssertEqual(recording.stops, 1)
    }

    @MainActor
    func testRequiredBindingsRejectDisabledAndValidatePersistedValues() throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = ShortcutPreferences(defaults: defaults)
        let monitor = FakeShortcutMonitor()
        let service = ShortcutService(preferences: preferences, monitor: monitor)
        let original = preferences.bindings()
        for action in [ShortcutAction.toggle, .cancel] {
            let disabled = ShortcutBinding(
                action: action, input: .keyboard(keyCode: 49, modifiers: 1 << 19), enabled: false)
            XCTAssertThrowsError(try service.save(disabled)) { error in
                XCTAssertEqual(
                    error as? ShortcutError, ShortcutError("This shortcut cannot be disabled"))
            }
            XCTAssertEqual(preferences.bindings(), original)
        }
        XCTAssertTrue(monitor.validated.isEmpty)
        let conflict = ShortcutBinding(
            action: .cancel, input: .keyboard(keyCode: 49, modifiers: 1 << 19), enabled: true)
        XCTAssertThrowsError(try service.save(conflict))
        XCTAssertTrue(monitor.validated.isEmpty)
        monitor.validation = .invalid("Unavailable")
        let candidate = ShortcutBinding(
            action: .cancel, input: .keyboard(keyCode: 42, modifiers: UInt64.max), enabled: true)
        XCTAssertThrowsError(try service.save(candidate))
        let effective = ShortcutBinding(
            action: .cancel, input: .keyboard(keyCode: 42, modifiers: UInt64(Int.max)),
            enabled: true)
        XCTAssertEqual(monitor.validated, [effective])
        XCTAssertEqual(preferences.bindings(), original)
        monitor.validation = .valid
        try service.save(candidate)
        XCTAssertEqual(preferences.bindings().bindings.first { $0.action == .cancel }, effective)
    }

}
