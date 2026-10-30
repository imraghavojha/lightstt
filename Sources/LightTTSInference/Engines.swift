import Foundation
import AVFoundation
import FluidAudio
import CoreML
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
        params.flash_attn = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else { throw SpeechError.model("Could not load Whisper model: \(modelURL.path)") }
        context = ctx
    }
    deinit { whisper_free(context) }
    public func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SpeechError.audio("The transcription engine received an empty audio recording.") }
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false; params.print_realtime = false; params.print_timestamps = false
        params.no_context = true
        params.suppress_nst = true
        var performanceCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &performanceCores, &size, nil, 0) == 0, performanceCores > 0 { params.n_threads = performanceCores }
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
            let text = (0..<whisper_full_n_segments(context)).compactMap { whisper_full_get_segment_text(context, $0).map { String(cString: $0) } }.joined()
            return text.replacingOccurrences(of: #"\[[^\]\n]*\]|\([^()\n]*\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }, onCancel: { flag.cancel() })
    }
}

public actor ParakeetEngine: TranscriptionEngine {
    private let manager: AsrManager
    private let decoderLayers: Int
    public init(directory: URL, version: String) async throws {
        let variant = try InferenceParakeetVariant.resolve(version)
        self.decoderLayers = variant.decoderLayers
        let models: AsrModels
        if ["redux", "ultra", "tdt-ctc-110m", "ja"].contains(version) {
            let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
            models = try AsrModels.loadLocal(from: directory, version: variant, configuration: config)
        } else { models = try await AsrModels.load(from: directory, version: variant) }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        self.manager = manager
    }
    public func transcribe(samples: [Float]) async throws -> String { try Task.checkCancellation(); var state = try TdtDecoderState(decoderLayers: decoderLayers); let result = try await manager.transcribe(samples, decoderState: &state); try Task.checkCancellation(); return result.text }
}

import SherpaOnnx
import SherpaOnnxC

public actor SherpaEngine: TranscriptionEngine {
    private let recognizer: OpaquePointer
    public init(directory: URL, type: String, language: String = "en") throws {

        func file(_ name: String) -> String { directory.appendingPathComponent(name).path }
        let names = try SherpaModelFiles.requiredFiles(type)
        guard names.allSatisfy({ FileManager.default.fileExists(atPath: file($0)) }) else { throw SpeechError.model("Incomplete sherpa model") }
        let model: SherpaOnnxOfflineModelConfig
        switch type {
        case "moonshine":
            let moonshine = sherpaOnnxOfflineMoonshineModelConfig(preprocessor: file(names[0]), encoder: file(names[1]), uncachedDecoder: file(names[2]), cachedDecoder: file(names[3]))
            model = sherpaOnnxOfflineModelConfig(tokens: file("tokens.txt"), numThreads: 4, moonshine: moonshine)
        case "moonshine_v2":
            let moonshine = sherpaOnnxOfflineMoonshineModelConfig(encoder: file(names[0]), mergedDecoder: file(names[1]))
            model = sherpaOnnxOfflineModelConfig(tokens: file(names[2]), numThreads: 4, moonshine: moonshine)
        case "qwen3":
            let qwen = sherpaOnnxOfflineQwen3ASRModelConfig(convFrontend: file(names[0]), encoder: file(names[1]), decoder: file(names[2]), tokenizer: file("tokenizer"), maxTotalLen: 512, maxNewTokens: 128)
            model = sherpaOnnxOfflineModelConfig(tokens: "", numThreads: 4, qwen3Asr: qwen)
        case "sense_voice":
            model = sherpaOnnxOfflineModelConfig(tokens: file("tokens.txt"), numThreads: 4, senseVoice: sherpaOnnxOfflineSenseVoiceModelConfig(model: file("model.int8.onnx"), useInverseTextNormalization: true))
        case "zipformer":
            model = sherpaOnnxOfflineModelConfig(tokens: file(names[3]), transducer: sherpaOnnxOfflineTransducerModelConfig(encoder: file(names[0]), decoder: file(names[1]), joiner: file(names[2])), numThreads: 4)
        case "nemo_parakeet":
            model = sherpaOnnxOfflineModelConfig(tokens: file(names[3]), transducer: sherpaOnnxOfflineTransducerModelConfig(encoder: file(names[0]), decoder: file(names[1]), joiner: file(names[2])), numThreads: 4, modelType: "nemo_transducer")
        case "nemo_canary":
            guard ["en", "es", "de", "fr"].contains(language) else { throw SpeechError.model("This Canary model supports English, Spanish, German and French.") }
            model = sherpaOnnxOfflineModelConfig(tokens: file(names[2]), numThreads: 4, canary: sherpaOnnxOfflineCanaryModelConfig(encoder: file(names[0]), decoder: file(names[1]), srcLang: language, tgtLang: language))
        case "whisper_onnx":
            model = sherpaOnnxOfflineModelConfig(tokens: file(names[2]), whisper: sherpaOnnxOfflineWhisperModelConfig(encoder: file(names[0]), decoder: file(names[1]), language: "en"), numThreads: 4, modelType: "whisper")
        default:
            model = sherpaOnnxOfflineModelConfig(tokens: file("tokens.txt"), paraformer: sherpaOnnxOfflineParaformerModelConfig(model: file("model.int8.onnx")), numThreads: 4, modelType: "paraformer")
        }
        var config = sherpaOnnxOfflineRecognizerConfig(featConfig: sherpaOnnxFeatureConfig(sampleRate: 16000, featureDim: 80), modelConfig: model)
        guard let value = SherpaOnnxCreateOfflineRecognizer(&config) else { throw SpeechError.model("Could not load sherpa-onnx model") }; recognizer = value
    }
    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }
    public func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SpeechError.audio("The transcription engine received an empty audio recording.") }
        var texts: [String] = []
        // The C API does not expose an abort callback. Bound each synchronous decode
        // to 20 seconds of input and check cancellation between chunks.
        for start in stride(from: 0, to: samples.count, by: 320_000) {
            try Task.checkCancellation()
            guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { throw SpeechError.audio("Cannot create recognition stream") }
            let end = min(start + 320_000, samples.count)
            let text: String
            do {
                defer { SherpaOnnxDestroyOfflineStream(stream) }
                samples.withUnsafeBufferPointer { SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress?.advanced(by: start), Int32(end - start)) }
                SherpaOnnxDecodeOfflineStream(recognizer, stream)
                try Task.checkCancellation()
                guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { throw SpeechError.model("Recognition failed") }
                defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
                text = result.pointee.text.map { String(cString: $0) } ?? ""
            }
            if !text.isEmpty { texts.append(text) }
        }
        return texts.joined(separator: " ")
    }
}

import Speech

@available(macOS 26, *)
public actor AppleSpeechEngine: TranscriptionEngine {
    public init() {}
    public func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SpeechError.audio("The transcription engine received an empty audio recording.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { throw SpeechError.model("Apple Speech does not support the current locale") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw SpeechError.model("Install Apple Speech assets first") }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { throw SpeechError.audio("Cannot allocate audio") }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in if let base = source.baseAddress { channel.update(from: base, count: samples.count) } }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: temp) }
        do { let output = try AVAudioFile(forWriting: temp, settings: format.settings); try output.write(from: buffer) }
        let file = try AVAudioFile(forReading: temp)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let result = Task { () throws -> String in
            var text = ""
            for try await item in transcriber.results { text += String(item.text.characters) }
            return text
        }
        do { try await analyzer.start(inputAudioFile: file, finishAfterFile: true); return try await result.value }
        catch { result.cancel(); await analyzer.cancelAndFinishNow(); throw error }
    }
}

public actor CanaryEngine: TranscriptionEngine {
    private let manager: CanaryManager
    public init(directory: URL, language: String = "en") throws {
        guard let selected = CanaryLanguage(rawValue: language) else { throw SpeechError.model("Canary does not support the selected language.") }
        let config = MLModelConfiguration(); config.computeUnits = .cpuOnly
        func load(_ name: String) throws -> MLModel { try MLModel(contentsOf: directory.appendingPathComponent(name + ".mlmodelc"), configuration: config) }
        let models = try CanaryModels(preprocessor: load("Preprocessor"), encoder: load("EncoderInt4"), decoder: load("DecoderInt4"), projection: load("Projection"), tokenizer: Tokenizer(vocabPath: directory.appendingPathComponent("vocab.json")))
        manager = try CanaryManager(models: models, source: selected, target: selected)
    }
    public func transcribe(samples: [Float]) async throws -> String { try await manager.transcribe(audio: samples) }
}


public enum InferenceParakeetVariant {
    public static func resolve(_ value: String?) throws -> AsrModelVersion {
        switch value {
        case "v2": return .v2
        case "v3": return .v3
        case "ultra": return .ultra
        case "redux": return .redux
        case "tdt-ctc-110m": return .tdtCtc110m
        case "ja": return .tdtJa
        default: throw SpeechError.model("Unsupported Parakeet variant")
        }
    }
}
