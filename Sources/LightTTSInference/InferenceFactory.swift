import Foundation
import LightTTSCore
public enum InferenceFactory {
    public static func engine(for model: Model, cloudKey: String? = nil, cloudSession: URLSession? = nil) async throws -> any TranscriptionEngine {
        switch model.engine {
        case "cloud":
            guard let provider = model.cloudProvider, let name = model.cloudModel else { throw SpeechError.model("Cloud model configuration is incomplete.") }
            let cloud = try CloudEngine(provider: provider, model: name, apiKey: try cloudKey ?? CloudKeychain.read(id: model.id), baseURL: model.cloudEndpoint, session: cloudSession)
            if let id = model.fallbackID {
                let custom = UserDefaults.standard.data(forKey: "customModels").flatMap { try? JSONDecoder().decode([Model].self, from: $0) } ?? []
                if let local = (try ModelCatalog.load() + custom).first(where: { $0.id == id && $0.engine != "cloud" }), ModelStore.exists(local) { return CloudFallbackEngine(cloud: cloud, local: local) }
            }
            return cloud
        case "apple": if #available(macOS 26, *) { return AppleSpeechEngine() }; throw SpeechError.model("Apple Speech requires macOS 26 or later")
        case "canary": return try CanaryEngine(directory: ModelStore.path(model))
        case "sherpa": return try SherpaEngine(directory: ModelStore.path(model), type: model.version ?? "moonshine")
        case "parakeet": return try await ParakeetEngine(directory: ModelStore.path(model), version: model.version ?? "v3")
        case "whisper": return try WhisperCppEngine(modelURL: ModelStore.path(model))
        default: throw SpeechError.model("Unsupported engine: \(model.engine)")
        }
    }
}
