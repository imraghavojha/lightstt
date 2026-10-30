import Foundation
import LightTTSCore
import LightTTSInference
import FluidAudio
@main struct CLI {
    static func main() async {
        do {
            let args = CommandLine.arguments
            if args.count == 2, args[1] == "download-parakeet-v2" || args[1] == "download-parakeet-v3" { let id = String(args[1].dropFirst("download-".count)); guard let model = try ModelCatalog.load().first(where: { $0.id == id }) else { throw SpeechError.model("Unknown model") }; _ = try await AsrModels.download(to: ModelStore.path(model), version: model.version == "v2" ? .v2 : .v3); print(ModelStore.path(model).path); return }
            guard args.count == 4 else { throw SpeechError.model("Usage: lighttts-cli whisper MODEL_FILE AUDIO_FILE | parakeet-v2|parakeet-v3 MODEL_DIRECTORY AUDIO_FILE") }
            let model = URL(fileURLWithPath: args[2]); let samples = try AudioFileReader.read(URL(fileURLWithPath: args[3]))
            let engine: any TranscriptionEngine
            if args[1] == "whisper" { engine = try WhisperCppEngine(modelURL: model) }
            else if args[1] == "parakeet-v2" || args[1] == "parakeet-v3" { engine = try await ParakeetEngine(directory: model, version: String(args[1].suffix(2))) }
            else { throw SpeechError.model("Unknown engine") }
            print(try await engine.transcribe(samples: samples))
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
