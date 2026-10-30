import Foundation
import CryptoKit

public struct ModelFile: Codable, Hashable { public let path: String; public let url: URL; public let size: Int64; public let sha256: String; public init(path: String, url: URL, size: Int64, sha256: String) { self.path = path; self.url = url; self.size = size; self.sha256 = sha256 } }

public struct Model: Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let engine: String
    public let url: URL?
    public let version: String?
    public var size: Int64? = nil
    public var sha256: String? = nil
    public var speed: Int? = nil
    public var accuracy: Int? = nil
    public var languages: [String]? = nil
    public var files: [ModelFile]? = nil
    public var cloudProvider: CloudProvider? = nil
    public var cloudModel: String? = nil
    public var cloudEndpoint: URL? = nil
    public var fallbackID: String? = nil
    public init(id: String, name: String, engine: String, url: URL? = nil, version: String? = nil, sha256: String? = nil, size: Int64? = nil) { self.id = id; self.name = name; self.engine = engine; self.url = url; self.version = version; self.sha256 = sha256; self.size = size }
}
public enum ModelCatalog {
    public static func load() throws -> [Model] {
        let catalog = try JSONDecoder().decode([Model].self, from: Data(contentsOf: Bundle.module.url(forResource: "models", withExtension: "json")!))
        return catalog.filter { model in
            if model.engine == "apple" { if #available(macOS 26, *) { return true }; return false }
            if model.engine == "canary" || model.version == "redux" { if #available(macOS 15, *) { return true }; return false }
            return true
        }
    }
}
public enum ParakeetVariant {
    public static func folder(_ value: String?) -> String {
        switch value { case "ultra": return "parakeet-ultra"; case "redux": return "parakeet-redux"; case "tdt-ctc-110m": return "parakeet-tdt-ctc-110m"; case "ja": return "parakeet-ja"; default: return "parakeet-tdt-0.6b-" + (value ?? "v3") }
    }
}
private final class AppleAssetCache: @unchecked Sendable {
    static let shared = AppleAssetCache()
    private let lock = NSLock()
    private var locale = ""
    private var installed = false
    func get(_ current: String) -> Bool { lock.lock(); defer { lock.unlock() }; return locale == current && installed }
    func set(_ current: String, _ value: Bool) { lock.lock(); locale = current; installed = value; lock.unlock() }
}
public enum ModelStore {
    public static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LightTTS/Models", isDirectory: true)
    public static func path(_ model: Model) -> URL {
        let root = model.engine == "parakeet" && model.id.hasPrefix("custom-") ? directory.appendingPathComponent(model.id, isDirectory: true) : directory
        return root.appendingPathComponent(model.engine == "parakeet" ? ParakeetVariant.folder(model.version) : model.id, isDirectory: model.engine == "parakeet" || model.engine == "sherpa" || model.engine == "canary")
    }
    public static func exists(_ model: Model) -> Bool { if model.engine == "cloud" { return true }; if model.engine == "apple" { return FileManager.default.fileExists(atPath: directory.appendingPathComponent(".apple-speech-installed").path) }; if model.engine == "parakeet" { return FileManager.default.fileExists(atPath: path(model).appendingPathComponent("Encoder.mlmodelc").path) }; if model.engine == "canary" { return ["Preprocessor", "EncoderInt4", "DecoderInt4", "Projection"].allSatisfy { FileManager.default.fileExists(atPath: path(model).appendingPathComponent($0 + ".mlmodelc").path) } }; if model.engine == "sherpa" { guard let files = model.files, !files.isEmpty else { return false }; return files.allSatisfy { FileManager.default.fileExists(atPath: path(model).appendingPathComponent($0.path).path) } }; return FileManager.default.fileExists(atPath: path(model).path) }
    public static func delete(_ model: Model) throws { if model.engine == "cloud" { try CloudKeychain.remove(id: model.id); return }; if model.engine == "apple" { try? FileManager.default.removeItem(at: directory.appendingPathComponent(".apple-speech-installed")); return }; try FileManager.default.removeItem(at: path(model)) }
    public static func download(_ model: Model, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if model.engine == "sherpa" || (model.id.hasPrefix("custom-") && model.files != nil) {
            guard let files = model.files, !files.isEmpty else { throw SpeechError.model("Model files missing") }
            let stage = directory.appendingPathComponent(".stage-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: stage) }
            let total = Double(files.reduce(Int64(0)) { $0 + $1.size }); var completed: Int64 = 0
            for file in files {
                guard !file.path.hasPrefix("/"), file.path.split(separator: "/").allSatisfy({ $0 != "." && $0 != ".." }) else { throw SpeechError.model("Invalid model file path") }
                let before = completed
                let (temporary, response) = try await URLSession.shared.download(for: URLRequest(url: file.url), delegate: DownloadProgressDelegate { part in progress((Double(before) + part * Double(file.size)) / total) })
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw SpeechError.model("Model download failed") }
                try verifyChecksum(temporary, expected: file.sha256)
                try Task.checkCancellation()
                let target = stage.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: temporary, to: target)
                completed += file.size
            }
            try replaceDirectory(stage, destination: path(model)) { exists(model) }
            return
        }

        if ["apple", "canary", "parakeet"].contains(model.engine) { try await HelperDownload.run(model); progress(1); return }

        guard let url = model.url, url.scheme?.lowercased() == "https", let hash = model.sha256, hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { throw SpeechError.model("An HTTPS URL and SHA-256 are required") }
        let staged = try await ModelDownload(resumeURL: directory.appendingPathComponent(".resume-" + model.id), progress: progress).run(url: url)
        defer { try? FileManager.default.removeItem(at: staged) }
        try ModelValidation.verify(staged, sha256: hash, size: model.size)
        try Task.checkCancellation()
        guard rename(staged.path, path(model).path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    public static func refreshAppleStatus() async {}
    private static func replaceDirectory(_ staged: URL, destination: URL, validate: () -> Bool) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = destination.deletingLastPathComponent().appendingPathComponent(".backup-" + UUID().uuidString)
        let hadOld = fm.fileExists(atPath: destination.path)
        if hadOld { try fm.moveItem(at: destination, to: backup) }
        var moved = false
        do {
            try fm.moveItem(at: staged, to: destination); moved = true
            guard validate() else { throw SpeechError.model("Downloaded bundle is missing required files") }
            if hadOld { try? fm.removeItem(at: backup) }
        } catch {
            if moved { try? fm.removeItem(at: destination) }
            if hadOld && !fm.fileExists(atPath: destination.path) { try? fm.moveItem(at: backup, to: destination) }
            throw error
        }
    }
    private static func verifyChecksum(_ url: URL, expected: String) throws {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else { throw SpeechError.model("Model checksum mismatch") }
    }
    public static func importDirectory(_ source: URL, model: Model) throws {
        let destination = path(model)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        guard exists(model) else { try? FileManager.default.removeItem(at: destination); throw SpeechError.model("This folder is missing required model files") }
    }
    public static func importFile(_ url: URL, id: String) throws {
        try ModelValidation.verify(url, sha256: nil, size: nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent(id))
    }


}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(_ progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
