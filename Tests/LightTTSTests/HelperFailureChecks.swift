import Foundation
import AVFoundation

enum LaunchTrace { static func mark(_ text: String) {} }
@main struct Checks {
    static func script(_ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
    @MainActor static func main() async throws {
        let url = try script("trap '' TERM\nwhile :; do sleep 1; done")
        defer { try? FileManager.default.removeItem(at: url) }
        let helper = try HelperEngine(executableURL: url, warmTimeout: 0.1)
        do { _ = try await helper.request(action: "warm"); fatalError("expected timeout") }
        catch { precondition(error.localizedDescription.contains("timed out")) }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        precondition(!helper.isRunning, "hung helper must be killed")
        let next = try HelperEngine(executableURL: url, warmTimeout: 30)
        let task = Task { try await next.request(action: "warm") }
        try await Task.sleep(nanoseconds: 100_000_000); task.cancel()
        do { _ = try await task.value; fatalError("expected cancellation") } catch is CancellationError {}
        try await Task.sleep(nanoseconds: 1_500_000_000)
        precondition(!next.isRunning, "cancelled helper must be killed")
        let replacement = try HelperEngine(executableURL: url)
        precondition(replacement.isRunning); replacement.terminate()
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { unsetenv("LIGHTTTS_TEST_AUDIO"); try? FileManager.default.removeItem(at: wav) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        do {
            let file = try AVAudioFile(forWriting: wav, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160000)!
            buffer.frameLength = 160000; try file.write(from: buffer)
        }
        setenv("LIGHTTTS_TEST_AUDIO", wav.path, 1)
        UserDefaults.standard.set(false, forKey: "pushToTalk")
        let controller = AppController(); controller.start()
        precondition(controller.state == "recording")
        let capture = controller.audio!
        let crashScript = try script("sleep 0.2\nexit 1")
        defer { try? FileManager.default.removeItem(at: crashScript) }
        let crashing = try HelperEngine(executableURL: crashScript) { Task { @MainActor in controller.fail("Speech engine exited unexpectedly. Try recording again.") } }
        try await Task.sleep(nanoseconds: 600_000_000)
        precondition(controller.state == "error" && controller.message.contains("exited unexpectedly"))
        precondition(!capture.isActive && controller.audio == nil)
        controller.handleShortcut(true); controller.handleShortcut(false)
        precondition(controller.state == "recording", "next shortcut should start capture")
        controller.cancel(); withExtendedLifetime(crashing) {}
        print("helper timeout, cancellation, relaunch and capture crash checks passed")
    }
}
