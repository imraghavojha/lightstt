import Foundation
import FluidAudio

public struct Model: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let engine: String
    public let url: URL?
    public let version: String?
    public init(id: String, name: String, engine: String, url: URL? = nil, version: String? = nil) { self.id = id; self.name = name; self.engine = engine; self.url = url; self.version = version }
}
public enum ModelCatalog {
    public static func load() throws -> [Model] { try JSONDecoder().decode([Model].self, from: Data(contentsOf: Bundle.module.url(forResource: "models", withExtension: "json")!)) }
}
public enum ModelStore {
    public static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LightTTS/Models", isDirectory: true)
    public static func path(_ model: Model) -> URL { directory.appendingPathComponent(model.engine == "parakeet" ? "parakeet-tdt-0.6b-" + (model.version ?? "v3") : model.id, isDirectory: model.engine == "parakeet") }
    public static func exists(_ model: Model) -> Bool { if model.engine == "parakeet" { return AsrModels.modelsExist(at: path(model), version: model.version == "v2" ? .v2 : .v3) }; return FileManager.default.fileExists(atPath: path(model).path) }
    public static func delete(_ model: Model) throws { try FileManager.default.removeItem(at: path(model)) }
    public static func download(_ model: Model) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if model.engine == "parakeet" { _ = try await AsrModels.download(to: path(model), version: model.version == "v2" ? .v2 : .v3); return }
        guard let url = model.url else { throw SpeechError.model("Model URL missing") }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SpeechError.model("Model download failed") }
        if exists(model) { try delete(model) }
        try FileManager.default.moveItem(at: temporary, to: path(model))
    }
    public static func importFile(_ url: URL, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(id))
    }
    public static func engine(for model: Model) async throws -> any TranscriptionEngine {
        if model.engine == "parakeet" { return try await ParakeetEngine(directory: path(model), version: model.version ?? "v3") }
        return try WhisperCppEngine(modelURL: path(model))
    }
}
