import Foundation
import LightTTSRuntime
import XCTest

@MainActor
private final class TestEngine: EngineClient {
    var terminations = 0
    var failure: Error?
    var pending: CheckedContinuation<String, Error>?
    var started: CheckedContinuation<Void, Never>?
    var suspend = false
    var terminationWaiter: CheckedContinuation<Void, Never>?

    func transcribe(_ audio: PCM16k) async throws -> String {
        if let failure { throw failure }
        if suspend {
            return try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                started?.resume()
                started = nil
            }
        }
        return "text"
    }

    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func terminate() {
        terminations += 1
        terminationWaiter?.resume()
        terminationWaiter = nil
    }

    func waitUntilTerminated() async {
        if terminations > 0 { return }
        await withCheckedContinuation { terminationWaiter = $0 }
    }
}

@MainActor
private final class TestFactory: EngineClientFactory {
    struct Request {
        let configuration: EngineConfiguration
        let crash: @MainActor @Sendable () -> Void
        let continuation: CheckedContinuation<any EngineClient, Error>
    }
    var requests: [Request] = []
    var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var cancellations = 0
    var cancellationWaiter: CheckedContinuation<Void, Never>?

    func load(
        _ configuration: EngineConfiguration, onCrash: @escaping @MainActor @Sendable () -> Void
    ) async throws -> any EngineClient {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(
                    Request(
                        configuration: configuration, crash: onCrash, continuation: continuation))
                let ready = waiters.filter { $0.0 <= requests.count }
                waiters.removeAll { $0.0 <= requests.count }
                for (_, waiter) in ready { waiter.resume() }
            }
        } onCancel: {
            Task { @MainActor in
                self.cancellations += 1
                self.cancellationWaiter?.resume()
                self.cancellationWaiter = nil
            }
        }
    }

    func waitForCancellation() async {
        if cancellations > 0 { return }
        await withCheckedContinuation { cancellationWaiter = $0 }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

@MainActor
final class TranscriptionServiceTests: XCTestCase {
    private let a = EngineConfiguration(modelID: "model", language: "en")
    private let b = EngineConfiguration(modelID: "model", language: "fr")
    private let audio = PCM16k(samples: [0.1])

    func testWarmReuseConfigurationIdentityAndStaleCompletion() async throws {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        service.warm(a)
        service.warm(a)
        await factory.waitForRequests(1)
        XCTAssertEqual(factory.requests.count, 1)
        let first = TestEngine()
        service.warm(b)
        await factory.waitForRequests(2)
        factory.requests[0].continuation.resume(returning: first)
        let second = TestEngine()
        factory.requests[1].continuation.resume(returning: second)
        try await service.prepare(b)
        await first.waitUntilTerminated()
        XCTAssertEqual(first.terminations, 1)
        XCTAssertEqual(service.snapshot.loaded, b)
        factory.requests[0].crash()
        XCTAssertEqual(service.snapshot.loaded, b)
        factory.requests[1].crash()
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(second.terminations, 1)
    }

    func testLoadAndInferenceFailuresClearState() async {
        struct Failure: Error {}
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let load = Task { try await service.prepare(a) }
        await factory.waitForRequests(1)
        factory.requests[0].continuation.resume(throwing: Failure())
        do {
            try await load.value
            XCTFail("Expected load failure")
        } catch is Failure {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(service.snapshot.warming)
        let engine = TestEngine()
        engine.failure = Failure()
        let inference = Task { try await service.transcribe(audio, using: a, purpose: .live) }
        await factory.waitForRequests(2)
        factory.requests[1].continuation.resume(returning: engine)
        do {
            _ = try await inference.value
            XCTFail("Expected inference failure")
        } catch is Failure {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)
    }

    func testCancelAndIndependentHistoryWorker() async throws {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let live = Task { try await service.transcribe(audio, using: a, purpose: .live) }
        await factory.waitForRequests(1)
        let liveEngine = TestEngine()
        liveEngine.suspend = true
        factory.requests[0].continuation.resume(returning: liveEngine)
        await liveEngine.waitUntilStarted()
        let history = Task {
            try await service.transcribe(audio, using: a, purpose: .history(entryID: UUID()))
        }
        await factory.waitForRequests(2)
        let historyEngine = TestEngine()
        factory.requests[1].continuation.resume(returning: historyEngine)
        let historyResult = try await history.value
        XCTAssertEqual(historyResult, "text")
        XCTAssertEqual(historyEngine.terminations, 1)
        XCTAssertEqual(liveEngine.terminations, 0)
        live.cancel()
        liveEngine.pending?.resume(returning: "ignored")
        do {
            _ = try await live.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(liveEngine.terminations, 1)
    }

    func testCancellationDuringWarmDiscardsLateHelper() async {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let task = Task { try await service.transcribe(audio, using: a, purpose: .live) }
        await factory.waitForRequests(1)
        task.cancel()
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        await engine.waitUntilTerminated()
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)
    }

    func testSolePrepareCancellationCancelsLoadAndDiscardsLateHelper() async {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let preparation = Task { try await service.prepare(a) }
        await factory.waitForRequests(1)
        preparation.cancel()
        await factory.waitForCancellation()
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        do {
            try await preparation.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)
    }

    func testCancellingOnePrepareKeepsSharedLoadAlive() async throws {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let first = Task { try await service.prepare(a) }
        await factory.waitForRequests(1)
        var second: Task<Void, Error>!
        await withCheckedContinuation { (started: CheckedContinuation<Void, Never>) in
            second = Task { @MainActor in
                started.resume()
                try await service.prepare(a)
            }
        }
        first.cancel()
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        do {
            try await first.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        try await second.value
        XCTAssertEqual(service.snapshot.loaded, a)
        XCTAssertEqual(engine.terminations, 0)
        service.shutdown()
    }

    func testShutdownCancelsHistoryLoadAndDiscardsLateHelper() async {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        let history = Task {
            try await service.transcribe(audio, using: a, purpose: .history(entryID: UUID()))
        }
        await factory.waitForRequests(1)
        service.shutdown()
        await factory.waitForCancellation()
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        do {
            _ = try await history.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(engine.terminations, 1)
    }

    func testReuseDoesNotResetIdleTimeoutAndDoneIsNotIdle() async throws {
        let factory = TestFactory()
        let scheduler = ManualScheduler()
        let service = TranscriptionService(factory: factory, scheduler: scheduler)
        let battery = ModelResidencyPolicy(keepLoaded: true, onACPower: false, unloadAfter: 10)
        service.updateResidency(policy: battery, phase: .idle)
        let preparation = Task { try await service.prepare(a) }
        await factory.waitForRequests(1)
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        try await preparation.value
        scheduler.advance(by: 9)
        service.warm(a)
        scheduler.advance(by: 1)
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)

        service.updateResidency(policy: battery, phase: .done)
        let next = Task { try await service.prepare(a) }
        await factory.waitForRequests(2)
        let second = TestEngine()
        factory.requests[1].continuation.resume(returning: second)
        try await next.value
        scheduler.advance(by: 100)
        XCTAssertEqual(service.snapshot.loaded, a)
        service.shutdown()
    }

    func testBatteryWithoutKeepLoadedUnloadsAfterInferenceDuringProcessing() async throws {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        service.updateResidency(
            policy: ModelResidencyPolicy(keepLoaded: false, onACPower: false, unloadAfter: 10),
            phase: .processing(.transcribing))
        let inference = Task { try await service.transcribe(audio, using: a, purpose: .live) }
        await factory.waitForRequests(1)
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        let result = try await inference.value
        XCTAssertEqual(result, "text")
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)
    }

    func testResidencyTransitionsAndUseReset() async throws {
        let factory = TestFactory()
        let scheduler = ManualScheduler()
        let service = TranscriptionService(factory: factory, scheduler: scheduler)
        let battery = ModelResidencyPolicy(keepLoaded: true, onACPower: false, unloadAfter: 10)
        let ac = ModelResidencyPolicy(keepLoaded: false, onACPower: true, unloadAfter: 10)
        let noKeep = ModelResidencyPolicy(keepLoaded: false, onACPower: false, unloadAfter: 10)
        service.updateResidency(policy: battery, phase: .idle)
        let preparation = Task { try await service.prepare(a) }
        await factory.waitForRequests(1)
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        try await preparation.value
        scheduler.advance(by: 9)
        let result = try await service.transcribe(audio, using: a, purpose: .live)
        XCTAssertEqual(result, "text")
        scheduler.advance(by: 9)
        XCTAssertEqual(service.snapshot.loaded, a)
        service.updateResidency(policy: ac, phase: .idle)
        scheduler.advance(by: 100)
        XCTAssertEqual(service.snapshot.loaded, a)
        service.updateResidency(policy: noKeep, phase: .recording)
        scheduler.advance(by: 100)
        XCTAssertEqual(service.snapshot.loaded, a)
        service.updateResidency(policy: noKeep, phase: .idle)
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(engine.terminations, 1)

        service.updateResidency(policy: battery, phase: .recording)
        let next = Task { try await service.prepare(a) }
        await factory.waitForRequests(2)
        let second = TestEngine()
        factory.requests[1].continuation.resume(returning: second)
        try await next.value
        scheduler.advance(by: 100)
        XCTAssertEqual(service.snapshot.loaded, a)
        service.updateResidency(policy: battery, phase: .idle)
        scheduler.advance(by: 10)
        XCTAssertNil(service.snapshot.loaded)
        XCTAssertEqual(second.terminations, 1)
    }

    func testInvalidationAndShutdownTerminateObsoleteWarm() async {
        let factory = TestFactory()
        let service = TranscriptionService(factory: factory, scheduler: ManualScheduler())
        service.warm(a)
        await factory.waitForRequests(1)
        service.invalidate(modelID: "other")
        XCTAssertEqual(service.snapshot.warming, a)
        service.invalidate(modelID: a.modelID)
        let engine = TestEngine()
        factory.requests[0].continuation.resume(returning: engine)
        service.warm(b)
        await factory.waitForRequests(2)
        service.shutdown()
        let other = TestEngine()
        factory.requests[1].continuation.resume(returning: other)
        await engine.waitUntilTerminated()
        await other.waitUntilTerminated()
        XCTAssertEqual(engine.terminations, 1)
        XCTAssertEqual(other.terminations, 1)
        XCTAssertNil(service.snapshot.loaded)
    }
}
