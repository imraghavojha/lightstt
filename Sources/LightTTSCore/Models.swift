import Foundation

public struct Model: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let engine: String
    public let url: URL?
    public let version: String?
    public let sha256: String?
    public let size: Int64?
    public init(id: String, name: String, engine: String, url: URL? = nil, version: String? = nil, sha256: String? = nil, size: Int64? = nil) { self.id = id; self.name = name; self.engine = engine; self.url = url; self.version = version; self.sha256 = sha256; self.size = size }
}
public enum ModelCatalog {
    public static func load() throws -> [Model] { try JSONDecoder().decode([Model].self, from: Data(contentsOf: Bundle.module.url(forResource: "models", withExtension: "json")!)) }
}
public enum ModelStore {
    public static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LightTTS/Models", isDirectory: true)
    public static func path(_ model: Model) -> URL { directory.appendingPathComponent(model.engine == "parakeet" ? "parakeet-tdt-0.6b-" + (model.version ?? "v3") : model.id, isDirectory: model.engine == "parakeet") }
    public static func exists(_ model: Model) -> Bool { if model.engine == "parakeet" { return ["Encoder.mlmodelc", "Decoder.mlmodelc", "Preprocessor.mlmodelc", model.version == "v2" ? "JointDecision.mlmodelc" : "JointDecisionv3.mlmodelc", "parakeet_vocab.json"].allSatisfy { FileManager.default.fileExists(atPath: path(model).appendingPathComponent($0).path) } }; return FileManager.default.fileExists(atPath: path(model).path) }
    public static func delete(_ model: Model) throws { try FileManager.default.removeItem(at: path(model)) }
    public static func download(_ model: Model, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if model.engine == "parakeet" { try await HelperDownload.run(model); return }
        guard let url = model.url, url.scheme?.lowercased() == "https", let hash = model.sha256, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw SpeechError.model("A HTTPS URL and SHA-256 are required") }
        let resumeURL = directory.appendingPathComponent(".resume-" + model.id)
        let staged = try await ModelDownload(resumeURL: resumeURL, progress: progress).run(url: url)
        defer { try? FileManager.default.removeItem(at: staged) }
        try ModelValidation.verify(staged, sha256: hash, size: model.size)
        try Task.checkCancellation()
        // Both paths are on the same volume; rename atomically replaces an existing file.
        guard rename(staged.path, path(model).path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    public static func importFile(_ url: URL, id: String) throws {
        try ModelValidation.verify(url, sha256: nil, size: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(id))
    }
}
