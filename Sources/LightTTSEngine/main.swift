import Foundation
import FluidAudio
import LightTTSCore
import LightTTSInference

@main struct Helper {
    static func main() async {
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "download" {
            do { _ = try await AsrModels.download(to: URL(fileURLWithPath: CommandLine.arguments[2]), version: CommandLine.arguments[3] == "v2" ? .v2 : .v3); return }
            catch { fputs("\(error)\n", stderr); exit(1) }
        }
        var engine: (any TranscriptionEngine)?
        while let line = readLine(), let data = line.data(using: .utf8) {
            guard let command = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            var response = Reply(text: nil, error: nil)
            do {
                switch command.action {
                case "warm":
                    guard let model = command.model else { throw SpeechError.model("Missing model") }
                    if model.engine == "parakeet" { engine = try await ParakeetEngine(directory: ModelStore.path(model), version: model.version ?? "v3") }
                    else { engine = try WhisperCppEngine(modelURL: ModelStore.path(model)) }
                case "transcribe":
                    guard let engine, let path = command.audio else { throw SpeechError.model("Engine is not ready") }
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    guard data.count % MemoryLayout<Float>.size == 0 else { throw SpeechError.audio("Invalid PCM data") }
                    let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                    response.text = try await engine.transcribe(samples: samples)
                default: throw SpeechError.model("Unknown helper command")
                }
            } catch { response.error = error.localizedDescription }
            if let result = try? JSONEncoder().encode(response) { try? result.write(to: URL(fileURLWithPath: command.reply), options: .atomic) }
        }
    }
}
struct Command: Codable { let action: String; let reply: String; var model: Model?; var audio: String? }
struct Reply: Codable { var text: String?; var error: String? }
