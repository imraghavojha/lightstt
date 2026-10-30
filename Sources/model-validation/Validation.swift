import Foundation
import CryptoKit
import LightTTSCore
import LightTTSInference
@main struct Validation {
    static func main() async throws {
        if CommandLine.arguments.contains("--apple-status") {
            await ModelStore.refreshAppleStatus()
            guard let model = try ModelCatalog.load().first(where: { $0.id == "apple-speech" }) else { print("Apple Speech unavailable"); return }
            print("Apple locale \(Locale.current.identifier), installed: \(ModelStore.exists(model))")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--custom-integrity"), CommandLine.arguments.indices.contains(index + 1) {
            for engine in ["canary", "parakeet"] {
                var model = Model(id: "custom-test-" + UUID().uuidString, name: "integrity", engine: engine)
                model.files = [ModelFile(path: "weights", url: URL(string: CommandLine.arguments[index + 1])!, size: 7, sha256: String(repeating: "0", count: 64))]
                defer { try? FileManager.default.removeItem(at: ModelStore.path(model)); if engine == "parakeet" { try? FileManager.default.removeItem(at: ModelStore.path(model).deletingLastPathComponent()) } }
                do { try await ModelStore.download(model); throw SpeechError.model("Corrupt custom \(engine) download was accepted") }
                catch { guard error.localizedDescription.contains("checksum mismatch") else { throw error } }
                guard !ModelStore.exists(model) else { throw SpeechError.model("Corrupt custom model was installed") }
            }
            print("Custom Core ML checksum rejection passed")
            return
        }
        if CommandLine.arguments.contains("--download-smoke") { try await downloadSmoke(); return }
        if let index = CommandLine.arguments.firstIndex(of: "--sherpa-cancellation"), CommandLine.arguments.indices.contains(index + 1) {
            guard let model = try ModelCatalog.load().first(where: { $0.id == "moonshine-tiny" }), ModelStore.exists(model) else { throw SpeechError.model("Install moonshine-tiny first") }
            let engine = try await InferenceFactory.engine(for: model)
            let samples = try AudioFileReader.read(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await engine.transcribe(samples: samples) }
            do { _ = try await task.value; throw SpeechError.model("Canceled Sherpa inference returned a result") } catch is CancellationError { print("Sherpa pre-cancellation passed") }
            return
        }
        if CommandLine.arguments.contains("--canary-owned") { try await canaryOwned(); return }
        if CommandLine.arguments.contains("--bundle-repair") { try await bundleRepair(); return }
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
    static func canaryOwned() async throws {
        let model = Model(id: "test-" + UUID().uuidString, name: "test", engine: "canary")
        let path = ModelStore.path(model)
        defer { try? FileManager.default.removeItem(at: path) }
        try await ModelStore.download(model)
        guard ModelStore.exists(model) else { throw SpeechError.model("Canary download is incomplete") }
        try ModelStore.delete(model)
        guard !FileManager.default.fileExists(atPath: path.path) else { throw SpeechError.model("Canary was not removed") }
        print("App-owned Canary install and removal passed")
    }
    static func bundleRepair() async throws {
        guard let source = try ModelCatalog.load().first(where: { $0.id == "moonshine-tiny" }) else { throw SpeechError.model("Missing Moonshine model") }
        var test = Model(id: "test-" + UUID().uuidString, name: "repair", engine: "sherpa", version: "moonshine")
        test.files = source.files
        let dest = ModelStore.path(test)
        defer { try? FileManager.default.removeItem(at: dest) }
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try Data("incomplete".utf8).write(to: dest.appendingPathComponent("tokens.txt"))
        try await ModelStore.download(test)
        guard ModelStore.exists(test) else { throw SpeechError.model("Incomplete model was not repaired") }
        print("Incomplete bundle repair passed")
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
