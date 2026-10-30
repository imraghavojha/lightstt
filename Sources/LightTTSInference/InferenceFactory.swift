import Foundation
import LightTTSCore
public enum InferenceFactory {
    public static func engine(for model: Model) async throws -> any TranscriptionEngine {
        switch model.engine {
        case "apple": if #available(macOS 26, *) { return AppleSpeechEngine() }; throw SpeechError.model("Apple Speech requires macOS 26 or later")
        case "canary": return try CanaryEngine(directory: ModelStore.path(model))
        case "sherpa": return try SherpaEngine(directory: ModelStore.path(model), type: model.version ?? "moonshine")
        case "parakeet": return try await ParakeetEngine(directory: ModelStore.path(model), version: model.version ?? "v3")
        case "whisper": return try WhisperCppEngine(modelURL: ModelStore.path(model))
        default: throw SpeechError.model("Unsupported engine: \(model.engine)")
        }
    }
}
