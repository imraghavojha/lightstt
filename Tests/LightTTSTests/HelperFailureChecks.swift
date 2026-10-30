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
        precondition(focusDisposition(role: "AXTextField", subrole: "AXSecureTextField", secureInput: false) == .secure)
        precondition(focusDisposition(role: "AXSecureTextField", subrole: nil, secureInput: false) == .secure)
        precondition(focusDisposition(role: "AXTextArea", subrole: nil, secureInput: true) == .secure)
        precondition(focusDisposition(role: "AXButton", subrole: nil, secureInput: false) == .unavailable)
        precondition(focusDisposition(role: nil, subrole: nil, secureInput: false) == .unavailable)
        precondition(focusDisposition(role: "AXTextArea", subrole: nil, secureInput: false) == .editable)
        var chunks: [String] = []
        do {
            try typeInChunks(String(repeating: "a", count: 70), expectedPID: 1, currentPID: { chunks.isEmpty ? 1 : 2 }) { chunks.append($0) }
            fatalError("expected app switch to abort typing")
        } catch FocusError.changed { precondition(chunks.count == 1 && chunks[0].count == 32) }
        let defaults = SettingsDefaults.store
        let keys = ["hotkeyCode", "hotkeyModifiers", "rightOption", "pushShortcutEnabled", "mouseShortcut"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) } } }
        defaults.removeObject(forKey: "hotkeyModifiers")
        defaults.set(false, forKey: "rightOption")
        defaults.set(0, forKey: "hotkeyCode")
        defaults.set(true, forKey: "pushShortcutEnabled")
        defaults.set(2, forKey: "mouseShortcut")
        let toggle = ShortcutButton(codeKey: "hotkeyCode", modifiersKey: "hotkeyModifiers", fallbackCode: 49, enabledKey: nil)
        let push = ShortcutButton(codeKey: "pushHotkeyCode", modifiersKey: "pushHotkeyModifiers", fallbackCode: 49, enabledKey: "pushShortcutEnabled")
        let mouse = MouseShortcutButton()
        precondition(toggle.title.contains("A") && mouse.title == "Mouse 3")
        defaults.removeObject(forKey: "hotkeyCode")
        defaults.set(false, forKey: "pushShortcutEnabled")
        defaults.set(-1, forKey: "mouseShortcut")
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
        precondition(toggle.title.contains("Space") && push.title == "Record shortcut" && mouse.title == "Record shortcut", "shortcut labels must refresh immediately")
        let replyScript = try script(#"while IFS= read -r line; do printf '%s\n' '{"text":"ok"}'; done"#)
        defer { try? FileManager.default.removeItem(at: replyScript) }
        let responsive = try HelperEngine(executableURL: replyScript, warmTimeout: 1)
        let response = try await responsive.request(action: "warm")
        precondition(response == "ok", "pipe reply should be decoded")
        responsive.terminate()
        let exitScript = try script("read line\nexit 1")
        defer { try? FileManager.default.removeItem(at: exitScript) }
        let exited = try HelperEngine(executableURL: exitScript, warmTimeout: 3)
        let exitStart = ProcessInfo.processInfo.systemUptime
        do { _ = try await exited.request(action: "warm"); fatalError("expected helper exit") }
        catch { precondition(error.localizedDescription.contains("exited unexpectedly")) }
        precondition(ProcessInfo.processInfo.systemUptime - exitStart < 2, "helper exit must wake a pending request")
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
