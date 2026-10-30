import Foundation
import AVFoundation
import AudioToolbox
import LightTTSCore
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward API keys or audio to a redirected host.
        guard let original = task.originalRequest?.url, let next = request.url, original.scheme == next.scheme, original.host == next.host, original.port == next.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public struct CloudUnavailable: LocalizedError, Sendable {
    public let errorDescription: String?
    public init(_ text: String) { self.errorDescription = text }
}
public actor CloudFallbackEngine: TranscriptionEngine {
    private let cloud: CloudEngine
    private let local: Model
    private let canaryLanguage: String
    public init(cloud: CloudEngine, local: Model, canaryLanguage: String = "en") { self.cloud = cloud; self.local = local; self.canaryLanguage = canaryLanguage }
    public func transcribe(samples: [Float]) async throws -> String {
        do { return try await cloud.transcribe(samples: samples) }
        catch is CloudUnavailable { return try await InferenceFactory.engine(for: local, canaryLanguage: canaryLanguage).transcribe(samples: samples) }
    }
}
public actor CloudEngine: TranscriptionEngine {
    private let provider: CloudProvider
    private let model: String
    private let key: String
    private let endpoint: URL?
    private let session: URLSession
    private let ownsSession: Bool
    public init(provider: CloudProvider, model: String, apiKey: String, baseURL: URL? = nil, session: URLSession? = nil) throws {
        guard !apiKey.isEmpty, !apiKey.contains("\r"), !apiKey.contains("\n"), !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, model.count <= 256, !model.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw SpeechError.model("A model and API key are required.") }
        guard provider == .compatible || provider.models.contains(model) else { throw SpeechError.model("Choose a supported cloud model.") }
        if provider == .compatible {
            guard let baseURL, baseURL.scheme?.lowercased() == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else { throw SpeechError.model("Enter an HTTPS base URL without credentials or a query.") }
        }
        self.provider = provider; self.model = model; self.key = apiKey; self.endpoint = baseURL
        if let session { self.session = session; self.ownsSession = false } else { self.ownsSession = true; let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 180; config.urlCache = nil; self.session = URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil) }
    }
    deinit { if ownsSession { session.invalidateAndCancel() } }
    public func transcribe(samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SpeechError.audio("No audio captured.") }
        let audio = try Self.encode(samples)
        if provider == .gemini && audio.count > 14_000_000 { throw SpeechError.audio("Audio is too large for Gemini's inline upload. Shorten the recording.") }
        if provider == .groq && audio.count > 25_000_000 { throw SpeechError.audio("Audio is too large for Groq's free upload limit. Shorten the recording.") }
        do { return try await send(audio) }
        catch is CancellationError { throw CancellationError() }
        catch let error as URLError { if error.code == .cancelled { throw CancellationError() }; if error.code == .timedOut { throw CloudUnavailable("Cloud transcription timed out. Try again or select an offline model.") }; throw CloudUnavailable("Cloud transcription is unavailable. Check your connection or select an offline model.") }
    }
    private static func encode(_ samples: [Float]) throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)), let channel = buffer.floatChannelData?[0] else { throw SpeechError.audio("Could not prepare audio for upload.") }
        buffer.frameLength = AVAudioFrameCount(samples.count); samples.withUnsafeBufferPointer { if let base = $0.baseAddress { channel.update(from: base, count: samples.count) } }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000]
        do { let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false); try file.write(from: buffer) }
        return try Data(contentsOf: url)
    }
    private func request(_ url: URL, contentType: String) -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 90; r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        switch provider { case .elevenlabs: r.setValue(key, forHTTPHeaderField: "xi-api-key"); case .gemini: r.setValue(key, forHTTPHeaderField: "x-goog-api-key"); default: r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return r
    }
    private func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechError.audio("Cloud provider returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else { throw SpeechError.audio("Cloud provider returned HTTP \(http.statusCode). Check the API key, model and account.") }
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw SpeechError.audio("Cloud provider returned an invalid response.") }
        return value
    }
    private func send(_ audio: Data) async throws -> String {
        if provider == .gemini {
            guard model.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }), let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { throw SpeechError.model("Invalid Gemini model name.") }
            var r = request(url, contentType: "application/json")
            r.httpBody = try JSONSerialization.data(withJSONObject: ["contents": [["parts": [["text": "Transcribe the speech verbatim. Return only the transcript."], ["inline_data": ["mime_type": "audio/m4a", "data": audio.base64EncodedString()]]]]]])
            let response = try await json(r)
            guard let candidates = response["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]], let text = parts.compactMap({ $0["text"] as? String }).first else { throw SpeechError.audio("Cloud provider returned no transcript.") }
            return text
        }
        let target: URL
        switch provider { case .groq: target = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!; case .elevenlabs: target = URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!; case .compatible: target = endpoint!.appendingPathComponent("audio/transcriptions"); case .gemini: throw SpeechError.model("Unsupported cloud provider.") }
        let boundary = "LightTTS-" + UUID().uuidString; var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(provider == .elevenlabs ? "model_id" : "model")\"\r\n\r\n\(model)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n"); body.append(audio); append("\r\n--\(boundary)--\r\n")
        var r = request(target, contentType: "multipart/form-data; boundary=\(boundary)"); r.httpBody = body
        guard let text = try await json(r)["text"] as? String else { throw SpeechError.audio("Cloud provider returned no transcript.") }; return text
    }
}
