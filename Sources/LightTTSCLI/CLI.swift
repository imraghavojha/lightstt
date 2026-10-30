import Foundation
import LightTTSCore
import LightTTSInference
@main struct CLI {
    static func main() async {
        do {
            let args = CommandLine.arguments
            await ModelStore.refreshAppleStatus()
            let catalog = try ModelCatalog.load()
            if args.count >= 4, args[1] == "cloud" {
                guard let provider = CloudProvider(rawValue: args[2]) else { throw SpeechError.model("Unknown cloud provider") }
                guard let key = ProcessInfo.processInfo.environment[provider.environmentKey], !key.isEmpty else { print("SKIP: \(provider.environmentKey) is not set"); return }
                let name = args.count > 4 ? args[4] : provider.models.first ?? ""
                let endpoint = args.count > 5 ? URL(string: args[5]) : nil
                let engine = try CloudEngine(provider: provider, model: name, apiKey: key, baseURL: endpoint)
                print(try await engine.transcribe(samples: AudioFileReader.read(URL(fileURLWithPath: args[3])))); return
            }
            if args.count == 3, args[1] == "download" {
                guard let model = catalog.first(where: { $0.id == args[2] }) else { throw SpeechError.model("Unknown model") }
                try await ModelStore.download(model) { progress in fputs("\r\(Int(progress * 100))%", stderr) }
                print("\n\(ModelStore.path(model).path)"); return
            }
            if args.count == 4, args[1] == "transcribe" {
                guard let model = catalog.first(where: { $0.id == args[2] }), ModelStore.exists(model) else { throw SpeechError.model("Model is not installed") }
                let engine = try await InferenceFactory.engine(for: model)
                print(try await engine.transcribe(samples: AudioFileReader.read(URL(fileURLWithPath: args[3])))); return
            }
            if args.count == 2, args[1].hasPrefix("download-parakeet-") {
                let id = String(args[1].dropFirst("download-".count))
                guard let model = catalog.first(where: { $0.id == id }) else { throw SpeechError.model("Unknown model") }
                try await ModelStore.download(model); print(ModelStore.path(model).path); return
            }
            guard args.count == 4 else { throw SpeechError.model("Usage: lighttts-cli cloud PROVIDER AUDIO_FILE [MODEL] [BASE_URL] | download MODEL_ID | transcribe MODEL_ID AUDIO_FILE | whisper MODEL_FILE AUDIO_FILE | parakeet-v2|parakeet-v3 MODEL_DIRECTORY AUDIO_FILE") }
            let model = URL(fileURLWithPath: args[2]); let samples = try AudioFileReader.read(URL(fileURLWithPath: args[3]))
            let engine: any TranscriptionEngine
            if args[1] == "whisper" { engine = try WhisperCppEngine(modelURL: model) }
            else if args[1].hasPrefix("parakeet-") { engine = try await ParakeetEngine(directory: model, version: String(args[1].dropFirst("parakeet-".count))) }
            else { throw SpeechError.model("Unknown engine") }
            print(try await engine.transcribe(samples: samples))
        } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
    }
}
