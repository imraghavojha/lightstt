import Foundation
import LightTTSCore

private struct HelperCommand: Codable { let action: String; let reply: String; var model: Model? = nil; var audio: String? = nil }
private struct HelperReply: Codable { let text: String?; let error: String? }

private final class HelperStopState: @unchecked Sendable {
    private let lock = NSLock()
    private var intentional = false
    func markIntentional() { lock.lock(); intentional = true; lock.unlock() }
    func wasIntentional() -> Bool { lock.lock(); defer { lock.unlock() }; return intentional }
}

final class HelperEngine: TranscriptionEngine, @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let directory: URL
    private let stopState = HelperStopState()
    private init(onCrash: @escaping @Sendable () -> Void) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lighttts-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LightTTSEngine")
        let stopState = self.stopState
        process.terminationHandler = { _ in if !stopState.wasIntentional() { onCrash() } }
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
    deinit { terminate(); try? FileManager.default.removeItem(at: directory) }
    func terminate() { stopState.markIntentional(); if process.isRunning { process.terminate() }; try? input.fileHandleForWriting.close() }
    static func load(_ model: Model, onCrash: @escaping @Sendable () -> Void = {}) async throws -> HelperEngine {
        let helper = try HelperEngine(onCrash: onCrash)
        _ = try await helper.request(action: "warm", model: model)
        return helper
    }
    func transcribe(samples: [Float]) async throws -> String {
        let audio = directory.appendingPathComponent(UUID().uuidString + ".pcm")
        defer { try? FileManager.default.removeItem(at: audio) }
        try samples.withUnsafeBytes { try Data($0).write(to: audio, options: .atomic) }
        return try await request(action: "transcribe", audio: audio.path) ?? ""
    }
    private func request(action: String, model: Model? = nil, audio: String? = nil) async throws -> String? {
        let reply = directory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: reply) }
        var data = try JSONEncoder().encode(HelperCommand(action: action, reply: reply.path, model: model, audio: audio))
        data.append(10)
        guard process.isRunning else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
        try input.fileHandleForWriting.write(contentsOf: data)
        while true {
            try Task.checkCancellation()
            if let data = try? Data(contentsOf: reply) {
                let result = try JSONDecoder().decode(HelperReply.self, from: data)
                if let error = result.error { throw SpeechError.model(error) }
                return result.text
            }
            guard process.isRunning else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
