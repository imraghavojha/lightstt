import Foundation
public enum SpeechError: LocalizedError {
    case model(String), audio(String)
    public var errorDescription: String? { switch self { case .model(let s), .audio(let s): return s } }
}

public protocol TranscriptionEngine: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}
