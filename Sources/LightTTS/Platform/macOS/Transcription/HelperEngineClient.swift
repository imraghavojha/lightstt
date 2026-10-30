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
