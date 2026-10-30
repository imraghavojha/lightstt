import Foundation
import AVFoundation
import FluidAudio
import whisper
import LightTTSCore

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}

public actor WhisperCppEngine: TranscriptionEngine {
    private let context: OpaquePointer
    public init(modelURL: URL) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else { throw SpeechError.model("Could not load Whisper model: \(modelURL.path)") }
        context = ctx
    }
    deinit { whisper_free(context) }
    public func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SpeechError.audio("No audio captured") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false; params.print_realtime = false; params.print_timestamps = false
        params.no_context = true
        let flag = CancellationFlag()
        params.abort_callback = { pointer in
            guard let pointer else { return false }
            return Unmanaged<CancellationFlag>.fromOpaque(pointer).takeUnretainedValue().isCancelled()
        }
        params.abort_callback_user_data = Unmanaged.passUnretained(flag).toOpaque()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            let status = samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
            try Task.checkCancellation()
            guard status == 0 else { throw SpeechError.model("Whisper inference failed (\(status))") }
            return (0..<whisper_full_n_segments(context)).compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }, onCancel: { flag.cancel() })
    }
}

public actor ParakeetEngine: TranscriptionEngine {
    private let manager: AsrManager
    public init(directory: URL, version: String) async throws {
        let variant: AsrModelVersion = version == "v2" ? .v2 : .v3
        let models = try await AsrModels.load(from: directory, version: variant)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }
    public func transcribe(samples: [Float]) async throws -> String { try Task.checkCancellation(); var state = try TdtDecoderState(); let result = try await manager.transcribe(samples, decoderState: &state); try Task.checkCancellation(); return result.text }
}

