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
    private var warmTask: Task<any EngineClient, Error>?
    private var generation = UUID()
    private var timer: (any ScheduledCancellation)?
    private var liveUses = 0
    private var historyClients: [UUID: any EngineClient] = [:]
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

    public func warm(_ configuration: EngineConfiguration) {
        if loaded == configuration || warming == configuration {
            resetTimer()
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
                return engine
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
        _ = try await task.value
        try Task.checkCancellation()
        guard generation == token, loaded == configuration else { throw CancellationError() }
    }

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
                let result = try await withTaskCancellationHandler {
                    try await prepare(configuration)
                    guard let engine = client, generation == token else {
                        throw CancellationError()
                    }
                    return try await engine.transcribe(audio)
                } onCancel: {
                    Task { @MainActor [weak self] in
                        if self?.generation == token { self?.clearLive() }
                    }
                }
                try Task.checkCancellation()
                guard generation == token else { throw CancellationError() }
                return result
            } catch {
                if generation == token { clearLive() }
                throw error
            }
        }
    }

    private func transcribeHistory(
        _ audio: PCM16k, configuration: EngineConfiguration
    ) async throws -> String {
        let id = UUID()
        let token = historyGeneration
        let engine = try await factory.load(configuration, onCrash: {})
        guard !Task.isCancelled, token == historyGeneration else {
            engine.terminate()
            throw CancellationError()
        }
        historyClients[id] = engine
        defer {
            historyClients.removeValue(forKey: id)
            engine.terminate()
        }
        let result = try await withTaskCancellationHandler {
            try await engine.transcribe(audio)
        } onCancel: {
            Task { @MainActor in engine.terminate() }
        }
        try Task.checkCancellation()
        guard token == historyGeneration else { throw CancellationError() }
        return result
    }

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
