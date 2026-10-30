import Foundation
public enum HelperDownload {
    public static func run(_ model: Model) async throws {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LightTTSEngine")
        process.arguments = ["download-model", String(data: try JSONEncoder().encode(model), encoding: .utf8)!]
        try process.run()
        await withTaskCancellationHandler(operation: {
            await Task.detached { process.waitUntilExit() }.value
        }, onCancel: { if process.isRunning { process.terminate() } })
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw SpeechError.model("Parakeet download failed.") }
    }
}
