import Foundation

@MainActor
public final class TranscriptionService: TranscriptionServicing {
    private let factory: any EngineClientFactory
    private let scheduler: any RuntimeScheduling
    private var policy = ModelResidencyPolicy(keepLoaded: true, onACPower: true, unloadAfter: 300)
    private var phase: RecordingPhase = .idle
    private var client: (any EngineClient)?
    private var loaded: EngineConfiguration?
    private var warming: EngineConfiguration?
    private var warmTask: Task<Void, Error>?
    private var warmWaiters: Set<UUID> = []
    private var generation = UUID()
    private var timer: (any ScheduledCancellation)?
    private var liveUses = 0
    private var historyClients: [UUID: any EngineClient] = [:]
    private var historyLoads: [UUID: Task<Void, Error>] = [:]
    private var historyGeneration = UUID()
    private var observers: [UUID: AsyncStream<TranscriptionSnapshot>.Continuation] = [:]

    public init(factory: any EngineClientFactory, scheduler: any RuntimeScheduling) {
        self.factory = factory
        self.scheduler = scheduler
    }

    public var snapshot: TranscriptionSnapshot {
        TranscriptionSnapshot(loaded: loaded, warming: warming)
    }

    public func snapshots() -> AsyncStream<TranscriptionSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.observers.removeValue(forKey: id) }
            }
        }
    }

    private func publish() {
        let value = snapshot
        for observer in observers.values {
            observer.yield(value)
        }
    }

    /// Starts a speculative load. Reusing a load does not extend its idle timeout.
    /// Callers initiate warming on AC connection and handle load or crash errors in their UI.
    public func warm(_ configuration: EngineConfiguration) {
        if loaded == configuration || warming == configuration {
            return
        }
        clearLive()
        let token = generation
        warming = configuration
        publish()
        let factory = self.factory
        warmTask = Task { [weak self] in
            do {
                let engine = try await factory.load(configuration) { [weak self] in
                    self?.crashed(token: token)
                }
                guard let self, self.generation == token else {
                    engine.terminate()
                    throw CancellationError()
                }
                self.client = engine
                self.loaded = configuration
                self.warming = nil
                self.warmTask = nil
                self.publish()
                self.resetTimer()
                return
            } catch {
                if let self, self.generation == token {
                    self.warming = nil
                    self.warmTask = nil
                    self.publish()
                    self.resetTimer()
                }
                throw error
            }
        }
        resetTimer()
    }

    public func prepare(_ configuration: EngineConfiguration) async throws {
        try Task.checkCancellation()
        warm(configuration)
        if loaded == configuration { return }
        guard let task = warmTask else { throw CancellationError() }
        let token = generation
        let waiter = UUID()
        warmWaiters.insert(waiter)
        defer { warmWaiters.remove(waiter) }
        try await withTaskCancellationHandler {
            try await task.value
            if Task.isCancelled {
                cancelWarmWaiter(waiter, token: token)
                throw CancellationError()
            }
            guard generation == token, loaded == configuration else { throw CancellationError() }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWarmWaiter(waiter, token: token)
            }
        }
    }

    private func cancelWarmWaiter(_ waiter: UUID, token: UUID) {
        guard generation == token, warmWaiters.remove(waiter) != nil else { return }
        if warmWaiters.isEmpty { clearLive() }
    }

    /// Callers serialize or defer history work when their recording workflow requires it.
    public func transcribe(
        _ audio: PCM16k, using configuration: EngineConfiguration, purpose: TranscriptionPurpose
    ) async throws -> String {
        switch purpose {
        case .history:
            return try await transcribeHistory(audio, configuration: configuration)
        case .live:
            liveUses += 1
            timer?.cancel()
            timer = nil
            defer {
                liveUses -= 1
                resetTimer()
            }
            warm(configuration)
            let token = generation
            do {
                try await prepare(configuration)
                guard let engine = client, generation == token else { throw CancellationError() }
                let result = try await withTaskCancellationHandler {
                    try await engine.transcribe(audio)
                } onCancel: {
                    Task { @MainActor [weak self] in
                        if self?.generation == token { self?.clearLive() }
                    }
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                if !policy.onACPower && !policy.keepLoaded { clearLive() }
                return result
            } catch {
                if !(error is CancellationError), generation == token { clearLive() }
                throw error
            }
        }
    }

    private func transcribeHistory(
        _ audio: PCM16k, configuration: EngineConfiguration
    ) async throws -> String {
        let id = UUID()
        let token = historyGeneration
        let factory = self.factory
        let load = Task { [weak self] in
            let engine = try await factory.load(configuration, onCrash: {})
            guard let self, !Task.isCancelled, token == self.historyGeneration else {
                engine.terminate()
                throw CancellationError()
            }
            self.historyClients[id] = engine
        }
        historyLoads[id] = load
        defer {
            historyLoads.removeValue(forKey: id)
            historyClients.removeValue(forKey: id)?.terminate()
        }
        return try await withTaskCancellationHandler {
            try await load.value
            try Task.checkCancellation()
            guard token == historyGeneration, let engine = historyClients[id] else {
                throw CancellationError()
            }
            let result = try await engine.transcribe(audio)
            try Task.checkCancellation()
            guard token == historyGeneration else { throw CancellationError() }
            return result
        } onCancel: {
            Task { @MainActor [weak self] in
                load.cancel()
                self?.historyClients.removeValue(forKey: id)?.terminate()
            }
        }
    }

    /// Callers must report power, preference, and recording phase changes as they occur.
    /// Callers provide preference defaults and refresh them when they change. A completed
    /// recording remains non-idle until the caller reports idle or error.
    public func updateResidency(policy: ModelResidencyPolicy, phase: RecordingPhase) {
        self.policy = policy
        self.phase = phase
        resetTimer()
    }

    public func invalidate(modelID: String?) {
        guard modelID == nil || loaded?.modelID == modelID || warming?.modelID == modelID else {
            return
        }
        clearLive()
    }

    public func shutdown() {
        clearLive()
        historyGeneration = UUID()
        for load in historyLoads.values { load.cancel() }
        historyLoads.removeAll()
        for engine in historyClients.values { engine.terminate() }
        historyClients.removeAll()
    }

    private func crashed(token: UUID) {
        guard token == generation else { return }
        clearLive()
    }

    private func clearLive() {
        generation = UUID()
        timer?.cancel()
        timer = nil
        warmTask?.cancel()
        warmTask = nil
        warmWaiters.removeAll()
        client?.terminate()
        client = nil
        loaded = nil
        warming = nil
        publish()
    }

    private func resetTimer() {
        timer?.cancel()
        timer = nil
        guard liveUses == 0, client != nil || warmTask != nil,
            let delay = policy.idleUnloadDelay(for: phase)
        else { return }
        if delay == 0 {
            clearLive()
        } else {
            let token = generation
            timer = scheduler.schedule(after: delay) { [weak self] in
                guard let self, self.generation == token, self.liveUses == 0,
                    self.policy.idleUnloadDelay(for: self.phase) != nil
                else { return }
                self.clearLive()
            }
        }
    }
}
