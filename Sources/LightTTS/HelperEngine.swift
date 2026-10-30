import Foundation
import Darwin
import LightTTSCore

private struct HelperCommand: Codable { let action: String; let reply: String?; var model: Model? = nil; var audio: String? = nil; var language: String? = nil }
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
    private let output = Pipe()
    private let requests = DispatchQueue(label: "com.lighttts.helper.requests", qos: .userInitiated)
    private let directory: URL
    private let stopState = HelperStopState()
    private let warmTimeout: TimeInterval
    private let transcribeTimeout: TimeInterval
    init(executableURL: URL? = nil, warmTimeout: TimeInterval = 120, transcribeTimeout: TimeInterval = 300, onCrash: @escaping @Sendable () -> Void = {}) throws {
        self.warmTimeout = warmTimeout; self.transcribeTimeout = transcribeTimeout
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("lighttts-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        process.executableURL = executableURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LightTTSEngine")
        let stopState = self.stopState
        process.terminationHandler = { _ in if !stopState.wasIntentional() { onCrash() } }
        process.standardInput = input
        process.standardOutput = output
        if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] != "1" { process.standardError = FileHandle.nullDevice }
        LaunchTrace.mark("helper-spawn-start")
        try process.run()
        LaunchTrace.mark("helper-spawned")
    }
    deinit { terminate(); try? FileManager.default.removeItem(at: directory) }
    var isRunning: Bool { process.isRunning }
    func terminate() {
        stopState.markIntentional()
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }
        process.terminate()
        // Process owns and reaps its child. Escalate if native inference ignores SIGTERM.
        let child = process
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
    }
    static func load(_ model: Model, language: String = "en", onCrash: @escaping @Sendable () -> Void = {}) async throws -> HelperEngine {
        let helper = try HelperEngine(onCrash: onCrash)
        LaunchTrace.mark("model-load-start")
        _ = try await helper.request(action: "warm", model: model, language: language)
        LaunchTrace.mark("model-load-finished")
        return helper
    }
    func transcribe(samples: [Float]) async throws -> String {
        let audio = directory.appendingPathComponent(UUID().uuidString + ".pcm")
        defer { try? FileManager.default.removeItem(at: audio) }
        LaunchTrace.mark("pcm-write-start")
        try samples.withUnsafeBytes { try Data($0).write(to: audio, options: .atomic) }
        LaunchTrace.mark("pcm-write-end")
        return try await request(action: "transcribe", audio: audio.path) ?? ""
    }
    func request(action: String, model: Model? = nil, audio: String? = nil, language: String? = nil) async throws -> String? {
        do { return try await performRequest(action: action, model: model, audio: audio, language: language) }
        catch { terminate(); if Task.isCancelled { throw CancellationError() }; throw error }
    }
    private func performRequest(action: String, model: Model?, audio: String?, language: String?) async throws -> String? {
        try Task.checkCancellation()
        let command = try JSONEncoder().encode(HelperCommand(action: action, reply: nil, model: model, audio: audio, language: language)) + Data([10])
        let timeout = action == "warm" ? warmTimeout : transcribeTimeout
        let result: HelperReply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requests.async { [self] in
                    do {
                        guard process.isRunning else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
                        LaunchTrace.mark("helper-request-write-start")
                        try input.fileHandleForWriting.write(contentsOf: command)
                        LaunchTrace.mark("helper-request-write-end")
                        let deadline = ProcessInfo.processInfo.systemUptime + timeout
                        var reply = Data()
                        let fd = output.fileHandleForReading.fileDescriptor
                        while true {
                            let remaining = deadline - ProcessInfo.processInfo.systemUptime
                            guard remaining > 0 else { throw SpeechError.model("Speech engine \(action) timed out. Try recording again.") }
                            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
                            if ready < 0 { if errno == EINTR { continue }; throw SpeechError.model("Speech engine reply failed. Try recording again.") }
                            if ready == 0 { continue }
                            var bytes = [UInt8](repeating: 0, count: 4096)
                            let count = read(fd, &bytes, bytes.count)
                            guard count > 0 else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
                            reply.append(contentsOf: bytes.prefix(count))
                            if reply.last == 10 { break }
                            guard reply.count < 16 * 1024 * 1024 else { throw SpeechError.model("Speech engine reply is too large.") }
                        }
                        LaunchTrace.mark("helper-reply-received")
                        continuation.resume(returning: try JSONDecoder().decode(HelperReply.self, from: reply))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.terminate() }
        try Task.checkCancellation()
        if let error = result.error { throw SpeechError.model(error) }
        return result.text
    }
}
