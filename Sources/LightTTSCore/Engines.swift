import Foundation
import AVFoundation
import FluidAudio
import whisper

public protocol TranscriptionEngine: Sendable {
    func transcribe(samples: [Float]) async throws -> String
}

public enum SpeechError: LocalizedError {
    case model(String), audio(String)
    public var errorDescription: String? { switch self { case .model(let s), .audio(let s): return s } }
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
        let status = samples.withUnsafeBufferPointer { whisper_full(context, params, $0.baseAddress, Int32($0.count)) }
        guard status == 0 else { throw SpeechError.model("Whisper inference failed (\(status))") }
        return (0..<whisper_full_n_segments(context)).compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
    public func transcribe(samples: [Float]) async throws -> String { var state = try TdtDecoderState(); return try await manager.transcribe(samples, decoderState: &state).text }
}

public enum AudioFileReader {
    public static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let input = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let converter = AVAudioConverter(from: input, to: target), let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(file.length)) else { throw SpeechError.audio("Unsupported audio file") }
        try file.read(into: source)
        let capacity = AVAudioFrameCount(ceil(Double(source.frameLength) * 16000 / input.sampleRate)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw SpeechError.audio("Cannot allocate audio buffer") }
        var supplied = false; var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData; return source
        }
        if let error { throw error }
        guard let data = output.floatChannelData?[0] else { throw SpeechError.audio("Cannot read audio samples") }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
