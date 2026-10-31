import Foundation
import LightTTSCore
import LightTTSRuntime

@MainActor
final class HelperEngineClientFactory: EngineClientFactory {
    private let resolveModel: @MainActor (String) throws -> Model

    init(resolveModel: @escaping @MainActor (String) throws -> Model) {
        self.resolveModel = resolveModel
    }

    func load(
        _ configuration: EngineConfiguration, onCrash: @escaping @MainActor @Sendable () -> Void
    ) async throws -> any EngineClient {
        let model = try resolveModel(configuration.modelID)
        let helper = try await HelperEngine.load(model, language: configuration.language) {
            Task { @MainActor in onCrash() }
        }
        return HelperEngineClient(helper: helper)
    }
}

@MainActor
private final class HelperEngineClient: EngineClient {
    private let helper: HelperEngine

    init(helper: HelperEngine) {
        self.helper = helper
    }

    func transcribe(_ audio: PCM16k) async throws -> String {
        try await helper.transcribe(samples: audio.samples)
    }

    func terminate() {
        helper.terminate()
    }
}

@MainActor
private final class NativeTimerCancellation: ScheduledCancellation {
    let timer: Timer
    init(_ timer: Timer) { self.timer = timer }
    func cancel() { timer.invalidate() }
}

@MainActor
private struct NativeTranscriptionScheduler: RuntimeScheduling {
    var wallTime: Date { Date() }
    var monotonicTime: TimeInterval { ProcessInfo.processInfo.systemUptime }
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
        -> any ScheduledCancellation
    {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        return NativeTimerCancellation(timer)
    }
}

@MainActor
func makeNativeTranscriptionService(
    resolveModel: @escaping @MainActor (String) throws -> Model,
    onFailure: @escaping @MainActor (String) -> Void
) -> TranscriptionService {
    TranscriptionService(
        factory: HelperEngineClientFactory(resolveModel: resolveModel),
        scheduler: NativeTranscriptionScheduler(), onFailure: onFailure
    )
}
