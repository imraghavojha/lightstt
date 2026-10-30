import Foundation
import CryptoKit
import LightTTSCore
@main struct Validation {
    static func main() async throws {
        if CommandLine.arguments.contains("--download-smoke") { try await downloadSmoke(); return }
        for model in try ModelCatalog.load().filter({ $0.engine == "whisper" }) {
            guard model.url?.scheme == "https", model.sha256?.count == 64, model.sha256?.allSatisfy(\.isHexDigit) == true, (model.size ?? 0) > 0 else { throw SpeechError.model("Invalid catalog entry: \(model.id)") }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = Data([0x6c, 0x6d, 0x67, 0x67, 1, 2, 3]); try data.write(to: url)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try ModelValidation.verify(url, sha256: hash, size: Int64(data.count))
        func rejects(_ body: () throws -> Void) throws { do { try body() } catch { return }; throw SpeechError.model("Invalid model was accepted") }
        try rejects { try ModelValidation.verify(url, sha256: String(repeating: "0", count: 64), size: nil) }
        try rejects { try ModelValidation.verify(url, sha256: hash, size: 8) }
        try Data("<html>".utf8).write(to: url)
        try rejects { try ModelValidation.verify(url, sha256: nil, size: nil) }
        print("Catalog and corrupt-model validation passed")
    }
    static func downloadSmoke() async throws {
        guard let base = try ModelCatalog.load().first(where: { $0.id == "whisper-tiny.en" }) else { throw SpeechError.model("Missing model") }
        let model = Model(id: "test-" + UUID().uuidString, name: "test", engine: "whisper", url: base.url, sha256: base.sha256, size: base.size)
        let resume = ModelStore.directory.appendingPathComponent(".resume-" + model.id)
        defer { try? FileManager.default.removeItem(at: ModelStore.path(model)); try? FileManager.default.removeItem(at: resume) }
        let task = Task { try await ModelStore.download(model) }
        try await Task.sleep(nanoseconds: 500_000_000); task.cancel()
        do { try await task.value } catch is CancellationError { }
        guard FileManager.default.fileExists(atPath: resume.path) else { throw SpeechError.model("Download produced no resume data") }
        try await ModelStore.download(model)
        guard ModelStore.exists(model) else { throw SpeechError.model("Resumed download did not install") }
        print("Download cancellation and resume passed")
    }
}
