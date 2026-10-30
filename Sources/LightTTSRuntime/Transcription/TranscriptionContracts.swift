import Foundation

public struct EngineConfiguration: Equatable, Sendable {
    public let modelID: String
    public let language: String
    public init(modelID: String, language: String) {
        self.modelID = modelID
        self.language = language
    }
}

public enum TranscriptionPurpose: Equatable, Sendable {
    case live
    case history(entryID: UUID)
}

public struct ModelResidencyPolicy: Equatable, Sendable {
    public let keepLoaded: Bool
    public let onACPower: Bool
    public let unloadAfter: TimeInterval
    public init(keepLoaded: Bool, onACPower: Bool, unloadAfter: TimeInterval) {
        self.keepLoaded = keepLoaded
        self.onACPower = onACPower
        self.unloadAfter = unloadAfter
    }
}

public struct TranscriptionSnapshot: Equatable, Sendable {
    public let loaded: EngineConfiguration?
    public let warming: EngineConfiguration?
    public init(loaded: EngineConfiguration?, warming: EngineConfiguration?) {
        self.loaded = loaded
        self.warming = warming
    }
}

@MainActor
public protocol TranscriptionServicing: StateSource where Snapshot == TranscriptionSnapshot {
    func warm(_ configuration: EngineConfiguration)
    func prepare(_ configuration: EngineConfiguration) async throws
    func transcribe(
        _ audio: PCM16k, using configuration: EngineConfiguration, purpose: TranscriptionPurpose
    ) async throws -> String
    func updateResidency(policy: ModelResidencyPolicy, phase: RecordingPhase)
    func invalidate(modelID: String?)
    func shutdown()
}

@MainActor
public protocol EngineClient: AnyObject {
    func transcribe(_ audio: PCM16k) async throws -> String
    func terminate()
}

@MainActor
public protocol EngineClientFactory {
    func load(
        _ configuration: EngineConfiguration, onCrash: @escaping @MainActor @Sendable () -> Void
    ) async throws -> any EngineClient
}
