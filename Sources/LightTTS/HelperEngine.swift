import Foundation
import Darwin
import LightTTSCore

private struct HelperCommand: Codable { let id: String; let action: String; var model: Model? = nil; var audio: String? = nil; var language: String? = nil }
private struct HelperReply: Codable { let id: String; let text: String?; let error: String? }
private struct ReplyProtocolError: LocalizedError { let message: String; var errorDescription: String? { message } }

private final class HelperProcessState: @unchecked Sendable {
    let lock = NSLock()
    var pid: pid_t = 0
    var running = false
}

private final class HelperStopState: @unchecked Sendable {
    private let lock = NSLock()
    private var intentional = false
    func markIntentional() { lock.lock(); intentional = true; lock.unlock() }
    func wasIntentional() -> Bool { lock.lock(); defer { lock.unlock() }; return intentional }
}

final class HelperEngine: TranscriptionEngine, @unchecked Sendable {
    private let processState = HelperProcessState()
    private var replyBuffer = Data()
    private var scannedReplyBytes = 0
    private var discardingOversizedReply = false
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
        let executable = executableURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LightTTSEngine")
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, input.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&actions, output.fileHandleForWriting.fileDescriptor, 3)
        if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] != "1" {
            posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        } else {
            posix_spawn_file_actions_addinherit_np(&actions, STDERR_FILENO)
        }
        posix_spawn_file_actions_adddup2(&actions, STDERR_FILENO, STDOUT_FILENO)
        for fd in [input.fileHandleForReading.fileDescriptor, input.fileHandleForWriting.fileDescriptor,
                   output.fileHandleForReading.fileDescriptor, output.fileHandleForWriting.fileDescriptor] where fd > 3 {
            posix_spawn_file_actions_addclose(&actions, fd)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["LIGHTTTS_REPLY_FD"] = "3"
        let env = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for entry in env { free(entry) } }
        let arg = strdup(executable.path)
        defer { free(arg) }
        var argv: [UnsafeMutablePointer<CChar>?] = [arg, nil]
        var envp = env
        LaunchTrace.mark("helper-spawn-start")
        // Close every descriptor not set up above, so a helper never inherits another helper's pipes.
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp)
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
        processState.pid = pid
        processState.running = true
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        let child = pid
        let stopState = self.stopState
        let processState = self.processState
        DispatchQueue.global(qos: .utility).async {
            // Keep the exited child unreaped until holding the lock, so a concurrent
            // signal cannot target a reused process ID.
            var info = siginfo_t()
            while waitid(P_PID, id_t(child), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
            processState.lock.lock()
            var status: Int32 = 0
            while waitpid(child, &status, 0) < 0 && errno == EINTR {}
            processState.running = false
            processState.lock.unlock()
            if !stopState.wasIntentional() { onCrash() }
        }
        LaunchTrace.mark("helper-spawned")
    }
    deinit { terminate(); try? FileManager.default.removeItem(at: directory) }
    var isRunning: Bool { processState.lock.lock(); defer { processState.lock.unlock() }; return processState.running }
    func terminate() {
        stopState.markIntentional()
        try? input.fileHandleForWriting.close()
        let state = processState
        state.lock.lock()
        if state.running { kill(state.pid, SIGTERM) }
        state.lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            state.lock.lock(); if state.running { kill(state.pid, SIGKILL) }; state.lock.unlock()
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
        catch { if !(error is ReplyProtocolError) { terminate() }; if Task.isCancelled { throw CancellationError() }; throw error }
    }
    private func performRequest(action: String, model: Model?, audio: String?, language: String?) async throws -> String? {
        try Task.checkCancellation()
        let id = UUID().uuidString
        let command = try JSONEncoder().encode(HelperCommand(id: id, action: action, model: model, audio: audio, language: language)) + Data([10])
        let timeout = action == "warm" ? warmTimeout : transcribeTimeout
        let result: HelperReply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requests.async { [self] in
                    do {
                        guard isRunning else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
                        LaunchTrace.mark("helper-request-write-start")
                        try input.fileHandleForWriting.write(contentsOf: command)
                        LaunchTrace.mark("helper-request-write-end")
                        let deadline = ProcessInfo.processInfo.systemUptime + timeout
                        let fd = output.fileHandleForReading.fileDescriptor
                        while true {
                            let scanStart = replyBuffer.index(replyBuffer.startIndex, offsetBy: scannedReplyBytes)
                            if let newline = replyBuffer[scanStart...].firstIndex(of: 10) {
                                let line = Data(replyBuffer[..<newline])
                                replyBuffer.removeSubrange(...newline)
                                scannedReplyBytes = 0
                                if discardingOversizedReply || line.count > 16 * 1024 * 1024 {
                                    discardingOversizedReply = false
                                    throw ReplyProtocolError(message: "Speech engine reply is too large.")
                                }
                                guard String(data: line, encoding: .utf8) != nil else {
                                    throw ReplyProtocolError(message: "Speech engine reply is not valid UTF-8.")
                                }
                                guard let reply = try? JSONDecoder().decode(HelperReply.self, from: line) else {
                                    NSLog("Ignoring malformed speech engine reply")
                                    continue
                                }
                                guard reply.id == id else { NSLog("Ignoring speech engine reply with unknown id: %@", reply.id); continue }
                                LaunchTrace.mark("helper-reply-received")
                                continuation.resume(returning: reply)
                                break
                            }
                            scannedReplyBytes = replyBuffer.count
                            if replyBuffer.count > 16 * 1024 * 1024 || discardingOversizedReply {
                                replyBuffer.removeAll(keepingCapacity: false); scannedReplyBytes = 0; discardingOversizedReply = true
                            }
                            let remaining = deadline - ProcessInfo.processInfo.systemUptime
                            guard remaining > 0 else { throw SpeechError.model("Speech engine \(action) timed out. Try recording again.") }
                            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                            let ready = poll(&descriptor, 1, Int32(min(remaining * 1000 + 1, Double(Int32.max))))
                            if ready < 0 { if errno == EINTR { continue }; throw SpeechError.model("Speech engine reply failed. Try recording again.") }
                            if ready == 0 { continue }
                            var bytes = [UInt8](repeating: 0, count: 4096)
                            let count = read(fd, &bytes, bytes.count)
                            guard count > 0 else { throw SpeechError.model("Speech engine exited unexpectedly. Try recording again.") }
                            replyBuffer.append(contentsOf: bytes.prefix(count))
                        }
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { self.terminate() }
        try Task.checkCancellation()
        if let error = result.error { throw SpeechError.model(error) }
        return result.text
    }
}
