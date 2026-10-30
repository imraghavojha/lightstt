import Foundation
import LightTTSRuntime
import XCTest

@MainActor
final class ManualScheduler: RuntimeScheduling {
    final class Token: ScheduledCancellation {
        var cancelled = false
        func cancel() {
            cancelled = true
        }
    }
    private struct Job {
        let deadline: TimeInterval
        let token: Token
        let action: @MainActor () -> Void
    }
    private var jobs: [Job] = []
    private(set) var wallTime = Date(timeIntervalSince1970: 0)
    private(set) var monotonicTime: TimeInterval = 0
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
        -> any ScheduledCancellation
    {
        let token = Token()
        jobs.append(Job(deadline: monotonicTime + max(0, delay), token: token, action: action))
        return token
    }
    func advance(by interval: TimeInterval) {
        precondition(interval >= 0)
        let target = monotonicTime + interval
        while let index = jobs.indices.filter({ jobs[$0].deadline <= target }).min(by: {
            jobs[$0].deadline < jobs[$1].deadline
        }) {
            let job = jobs.remove(at: index)
            wallTime.addTimeInterval(job.deadline - monotonicTime)
            monotonicTime = job.deadline
            if !job.token.cancelled {
                job.action()
            }
        }
        wallTime.addTimeInterval(target - monotonicTime)
        monotonicTime = target
    }
}

@MainActor
private final class Fakes: RecordingControlling, CaptureServicing,
    CaptureDriverFactory, EngineClient, EngineClientFactory, InsertionServicing, FocusCapturing,
    TranscriptClipboard, AudioDucking, RecordingCuePlaying, ShortcutMonitoring,
    RecordingPreferencesReading, TraceSink
{
    let recording = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    let transcription = TranscriptionSnapshot(loaded: nil, warming: nil)
    let shortcuts = ShortcutSnapshot(
        bindings: ShortcutBindings([]), editing: nil, registration: .installed)
    // Associated types require distinct wrappers for the three StateSource conformances.
    var snapshot: RecordingSnapshot { recording }
    func snapshots() -> AsyncStream<RecordingSnapshot> {
        AsyncStream {
            $0.yield(recording)
            $0.finish()
        }
    }
    func start(trigger: RecordingTrigger) {}
    func stop() {}
    func cancel() {}
    func dismissResult() {}
    func beginShutdown() {}
    func finishShutdown() async {}
    func start(deviceUID: String, onLevel: @escaping @MainActor @Sendable (Float) -> Void) throws {}
    func stop() -> CapturedAudio? {
        nil
    }
    func makeDriver() -> any CaptureDriver {
        FakeDriver()
    }
    func warm(_ configuration: EngineConfiguration) {}
    func prepare(_ configuration: EngineConfiguration) async throws {}
    func transcribe(
        _ audio: PCM16k, using configuration: EngineConfiguration, purpose: TranscriptionPurpose
    ) async throws -> String { "" }
    func updateResidency(policy: ModelResidencyPolicy, phase: RecordingPhase) {}
    func invalidate(modelID: String?) {}
    func shutdown() {}
    func transcribe(_ audio: PCM16k) async throws -> String {
        ""
    }
    func terminate() {}
    func load(
        _ configuration: EngineConfiguration, onCrash: @escaping @MainActor @Sendable () -> Void
    ) async throws -> any EngineClient { self }
    func captureAtStop() -> FocusTicket {
        FocusTicket { FocusResult(target: nil, disposition: .unavailable) }
    }
    func deliver(
        _ text: String, to focus: FocusTicket, autoPaste: Bool,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> InsertionOutcome { InsertionOutcome(delivery: .skipped) }
    func write(_ text: String, allowClipboardHistory: Bool) {}
    func begin(
        session: SessionID, options: DuckingOptions,
        onWarning: @escaping @MainActor @Sendable (String?) -> Void
    ) {}
    func end(session: SessionID) {}
    func waitForRestoration() async {}
    func play(_ cue: RecordingCue) {}
    var onEvent: ((ShortcutEvent) -> Void)?
    func install() -> Bool {
        true
    }
    func install(_ bindings: ShortcutBindings) -> ShortcutRegistrationResult {
        .installed
    }
    func setCancellationAvailable(_ available: Bool) {}
    func beginEditing(_ action: ShortcutAction) {}
    func save(_ binding: ShortcutBinding) throws {}
    func cancelEditing() {}
    func reset(_ action: ShortcutAction) throws {}
    func validate(_ binding: ShortcutBinding) -> ShortcutValidation {
        .valid
    }
    func startOptions() -> RecordingStartOptions {
        RecordingStartOptions(deviceUID: "", autoPaste: false)
    }
    func modelSelection() -> EngineConfiguration {
        EngineConfiguration(modelID: "", language: "")
    }
    func audioProcessingOptions() -> AudioProcessingOptions {
        AudioProcessingOptions(removeSilence: false, normalize: false)
    }
    func insertionOptions() -> InsertionOptions {
        InsertionOptions(
            simulateTyping: false, sendOnShift: false, restoreClipboard: false,
            allowClipboardHistory: false)
    }
    func residencyPolicy() -> ModelResidencyPolicy {
        ModelResidencyPolicy(keepLoaded: false, onACPower: false, unloadAfter: 0)
    }
    nonisolated func mark(_ stage: String) {}
}

@MainActor
private final class FakeDriver: CaptureDriver {
    func start(deviceUID: String, onLevel: @escaping @Sendable (Float) -> Void) throws {}
    func stop() -> PCM16k {
        PCM16k(samples: [])
    }
}

private final class FakeTarget: TextTarget, @unchecked Sendable {
    func insert(_ text: String) throws {}
    func type(_ text: String) throws {}
    func sendReturn() throws {}
}

@MainActor
private final class FakeTranscription: TranscriptionServicing {
    let base = Fakes()
    var snapshot: TranscriptionSnapshot { base.transcription }
    func snapshots() -> AsyncStream<TranscriptionSnapshot> {
        AsyncStream {
            $0.yield(snapshot)
            $0.finish()
        }
    }
    func warm(_ configuration: EngineConfiguration) {
        base.warm(configuration)
    }
    func prepare(_ configuration: EngineConfiguration) async throws {
        try await base.prepare(configuration)
    }
    func transcribe(
        _ audio: PCM16k, using configuration: EngineConfiguration, purpose: TranscriptionPurpose
    ) async throws -> String {
        try await base.transcribe(audio, using: configuration, purpose: purpose)
    }
    func updateResidency(policy: ModelResidencyPolicy, phase: RecordingPhase) {
        base.updateResidency(policy: policy, phase: phase)
    }
    func invalidate(modelID: String?) {
        base.invalidate(modelID: modelID)
    }
    func shutdown() {
        base.shutdown()
    }
}

@MainActor
private final class FakeShortcuts: ShortcutServicing {
    let base = Fakes()
    var snapshot: ShortcutSnapshot { base.shortcuts }
    func snapshots() -> AsyncStream<ShortcutSnapshot> {
        AsyncStream {
            $0.yield(snapshot)
            $0.finish()
        }
    }
    var onEvent: ((ShortcutEvent) -> Void)?
    func install() -> Bool {
        true
    }
    func stop() {}
    func setCancellationAvailable(_ available: Bool) {}
    func beginEditing(_ action: ShortcutAction) {}
    func save(_ binding: ShortcutBinding) throws {}
    func cancelEditing() {}
    func reset(_ action: ShortcutAction) throws {}
}

final class ContractSmokeTests: XCTestCase {
    @MainActor
    func testContractsAndScheduler() async {
        let fake = Fakes()
        let _: any RecordingControlling = fake
        let _: any CaptureServicing = fake
        let _: any CaptureDriver = FakeDriver()
        let _: any CaptureDriverFactory = fake
        let _: any TranscriptionServicing = FakeTranscription()
        let _: any EngineClient = fake
        let _: any EngineClientFactory = fake
        let _: any InsertionServicing = fake
        let _: any TextTarget = FakeTarget()
        let _: any FocusCapturing = fake
        let _: any TranscriptClipboard = fake
        let _: any AudioDucking = fake
        let _: any RecordingCuePlaying = fake
        let _: any ShortcutServicing = FakeShortcuts()
        let _: any ShortcutMonitoring = fake
        let _: any RecordingPreferencesReading = fake
        let _: any TraceSink = fake
        let scheduler = ManualScheduler()
        var events: [Int] = []
        _ = scheduler.schedule(after: 2) { events.append(2) }
        let cancelled = scheduler.schedule(after: 1) { events.append(1) }
        cancelled.cancel()
        scheduler.advance(by: 2)
        XCTAssertEqual(events, [2])
        XCTAssertEqual(scheduler.monotonicTime, 2)
    }
}
