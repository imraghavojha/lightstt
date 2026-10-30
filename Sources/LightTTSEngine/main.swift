import Foundation
import Darwin
import Speech
import FluidAudio
import LightTTSCore
import LightTTSInference

@main struct Helper {
    static func main() async {
        guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else { exit(1) }
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "download" {
            do { _ = try await AsrModels.download(to: URL(fileURLWithPath: CommandLine.arguments[2]), version: CommandLine.arguments[3] == "v2" ? .v2 : .v3); return }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "download-model" {
            do {
                let model = try JSONDecoder().decode(Model.self, from: Data(CommandLine.arguments[2].utf8))
                if model.engine == "apple" {
                    guard #available(macOS 26, *), let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else { throw SpeechError.model("Apple Speech unavailable") }
                    let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
                    guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw SpeechError.model("Apple Speech assets unavailable") }
                    try Data().write(to: ModelStore.directory.appendingPathComponent(".apple-speech-installed"), options: .atomic)
                } else if model.engine == "canary" {
                    let downloaded = try await CanaryModels.download()
                    try FileManager.default.copyItem(at: downloaded, to: ModelStore.path(model))
                } else if ["redux", "ultra", "tdt-ctc-110m", "ja"].contains(model.version ?? "") {
                    let repo: Repo = model.version == "redux" ? .parakeetRedux : model.version == "ultra" ? .parakeetUltra : model.version == "ja" ? .parakeetJa : .parakeetTdtCtc110m
                    try await ModelHub.download(repo, to: ModelStore.path(model).deletingLastPathComponent())
                } else { _ = try await AsrModels.download(to: ModelStore.path(model), version: try InferenceParakeetVariant.resolve(model.version)) }
                return
            } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        guard let value = ProcessInfo.processInfo.environment["LIGHTTTS_REPLY_FD"], let fd = Int32(value), fd > 2 else {
            fputs("Missing helper reply descriptor\n", stderr); exit(1)
        }
        let replyChannel = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var engine: (any TranscriptionEngine)?
        while let line = readLine(), let data = line.data(using: .utf8) {
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            trace("helper-received-\(command.action)")
            var response = Reply(id: command.id, text: nil, error: nil)
            do {
                switch command.action {
                case "warm":
                    guard let model = command.model else { throw SpeechError.model("Missing model") }
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LIGHTTTS_MOCK_CLOUD"] == "1", model.engine == "cloud" {
                        let config = URLSessionConfiguration.ephemeral
                        config.protocolClasses = [HelperMockCloudProtocol.self]
                        engine = try await InferenceFactory.engine(for: model, cloudKey: "unit-test-key", cloudSession: URLSession(configuration: config), canaryLanguage: command.language ?? "en")
                    } else { engine = try await InferenceFactory.engine(for: model, canaryLanguage: command.language ?? "en") }
                    #else
                    engine = try await InferenceFactory.engine(for: model, canaryLanguage: command.language ?? "en")
                    #endif
                case "transcribe":
                    guard let engine, let path = command.audio else { throw SpeechError.model("Engine is not ready") }
                    trace("helper-pcm-read-start")
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    guard data.count % MemoryLayout<Float>.size == 0 else { throw SpeechError.audio("Invalid PCM data") }
                    let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    trace("helper-pcm-read-end")
                    trace("helper-inference-start")
                    response.text = try await engine.transcribe(samples: samples)
                    trace("helper-inference-end")
                default: throw SpeechError.model("Unknown helper command")
                }
            } catch { response.error = error.localizedDescription }
            if let result = try? JSONEncoder().encode(response) {
                try? replyChannel.write(contentsOf: result + Data([10]))
            }
        }
    }
}
func trace(_ stage: String) {
    if ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1" { fputs("LightTTS trace: \(stage) mach=\(mach_absolute_time())\n", stderr) }
}
struct Command: Codable { let id: String; let action: String; var model: Model?; var audio: String?; var language: String? }
struct Reply: Codable { let id: String; var text: String?; var error: String? }
