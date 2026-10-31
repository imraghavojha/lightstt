import LightTTSRuntime
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
        precondition(focusDisposition(role: nil, subrole: nil, secureInput: false) == .uncertain)
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
        precondition(toggle.title.contains("Space") && push.title == "Disabled — record shortcut" && mouse.title == "Record shortcut", "shortcut labels must refresh immediately")
        let replyScript = try script(#"""
        exec /usr/bin/python3 -c '
        import json, os, sys, time
        out = os.fdopen(int(os.environ["LIGHTTTS_REPLY_FD"]), "wb", buffering=0)
        for line in sys.stdin:
            command = json.loads(line)
            action = command["action"]
            os.write(1, b"log before\n{}\n")
            if action == "invalid":
                out.write(b"\xff\n")
            elif action == "oversized":
                out.write(b"x" * (17 * 1024 * 1024) + b"\n")
            else:
                out.write(b"{}\n" + json.dumps({"id":"unknown", "text":"stale"}).encode() + b"\n")
                reply = json.dumps({"id": command["id"], "text": "a" * (2 * 1024 * 1024) if action == "large" else "ok"}).encode() + b"\n"
                out.write(reply[:7]); os.write(1, b"interleaved log\n"); out.write(reply[7:] + json.dumps({"id": "after", "text": "stale"}).encode() + b"\n")
                os.write(1, b"log after without newline")
        '
        """#)
        defer { try? FileManager.default.removeItem(at: replyScript) }
        let responsive = try HelperEngine(executableURL: replyScript, warmTimeout: 10, transcribeTimeout: 10)
        let firstResponse = try await responsive.request(action: "warm")
        precondition(firstResponse == "ok")
        let largeResponse = try await responsive.request(action: "large")
        precondition(largeResponse?.count == 2 * 1024 * 1024)
        for action in ["invalid", "oversized"] {
            do { _ = try await responsive.request(action: action); fatalError("expected protocol error") }
            catch { precondition(error.localizedDescription.contains(action == "invalid" ? "UTF-8" : "too large")) }
            precondition(responsive.isRunning, "bad frame should not kill the helper")
            let recovered = try await responsive.request(action: "warm")
            precondition(recovered == "ok", "reader must recover after bad frame")
        }
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
        let priorWindow = UserDefaults.standard.object(forKey: "recordingWindow")
        defer { if let priorWindow { UserDefaults.standard.set(priorWindow, forKey: "recordingWindow") } else { UserDefaults.standard.removeObject(forKey: "recordingWindow") } }
        UserDefaults.standard.set("Classic", forKey: "recordingWindow")
        let controller = AppController()
        precondition(UserDefaults.standard.string(forKey: "recordingWindow") == "Mini", "Classic must migrate to Mini")
        // Freeze the serial preparation after delivery, then exercise a new session,
        // deletion, migration, and quit while the old recording is still pending.
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        controller.historyPreparationHook = { entered.signal(); release.wait() }
        controller.showPreviewState("processing")
        let first = HistoryEntry(text: "delivered", date: Date())
        controller.commitDelivered(first, samples: [Float](repeating: 0.2, count: 16000), warning: nil, copied: false)
        precondition(entered.wait(timeout: .now() + 5) == .success)
        precondition(controller.state == "idle" && controller.history.contains(where: { $0.id == first.id }))
        do { try controller.changeHistoryFolder(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); fatalError("migration must wait for preparation") } catch {}
        controller.start()
        precondition(controller.state == "recording", "next session must start while history preparation is blocked")
        controller.cancel()
        precondition(controller.history.contains(where: { $0.id == first.id }), "new session cancellation must not discard delivered history")
        let second = HistoryEntry(text: "later", date: first.date.addingTimeInterval(1))
        controller.commitDelivered(second, samples: nil, warning: nil, copied: true)
        precondition(controller.history.first?.id == second.id)
        controller.deleteHistory(first.id)
        controller.historyPreparationHook = nil
        let third = HistoryEntry(text: "kept", date: first.date.addingTimeInterval(2))
        controller.commitDelivered(third, samples: [Float](repeating: 0.3, count: 32000), warning: nil, copied: false)
        controller.beginQuit()
        release.signal()
        await controller.finishQuit()
        let disk = try JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: controller.historyURL))
        precondition(disk.contains(where: { $0.id == second.id }) && !disk.contains(where: { $0.id == first.id }), "quit must flush deletion without resurrecting old history")
        let savedThird = disk.first { $0.id == third.id }!
        precondition(savedThird.waveform != nil && savedThird.segments != nil)
        precondition(FileManager.default.fileExists(atPath: controller.historyURL.deletingLastPathComponent().appendingPathComponent("Recordings/" + third.id.uuidString + ".wav").path), "quit must flush committed audio")
        controller.deleteHistory(second.id); controller.deleteHistory(third.id)
        await controller.finishQuit()
        precondition(!FileManager.default.fileExists(atPath: controller.historyURL.deletingLastPathComponent().appendingPathComponent("Recordings/" + first.id.uuidString + ".wav").path))
        controller.historyPreparationHook = nil
        print("delayed history delivery, new session, migration guard, deletion and quit checks passed")
        controller.start()
        precondition(controller.state == "recording" && controller.recordingPanelVisible)
        UserDefaults.standard.set("None", forKey: "recordingWindow")
        controller.refreshRecordingWindow()
        precondition(controller.state == "recording" && !controller.recordingPanelVisible, "None must hide the panel without stopping capture")
        let crashScript = try script("sleep 0.2\nexit 1")
        defer { try? FileManager.default.removeItem(at: crashScript) }
        let crashing = try HelperEngine(executableURL: crashScript) { Task { @MainActor in controller.fail("Speech engine exited unexpectedly. Try recording again.") } }
        try await Task.sleep(nanoseconds: 600_000_000)
        precondition(controller.state == "error" && controller.recordingPanelVisible && controller.message.contains("exited unexpectedly"), "errors must remain visible in None mode")
        controller.handleShortcut(true); controller.handleShortcut(false)
        precondition(controller.state == "recording", "next shortcut should start capture")
        controller.cancel()
        precondition(controller.state == "idle" && !controller.recordingPanelVisible, "cancel must hide the panel")
        UserDefaults.standard.set("Mini", forKey: "recordingWindow")
        for sessionState in ["processing", "loading"] {
            controller.showPreviewState(sessionState)
            precondition(controller.recordingPanelVisible)
            controller.handleShortcut(true)
            precondition(controller.state == "idle" && !controller.recordingPanelVisible, "toggle must cancel \(sessionState)")
            controller.showPreviewState(sessionState)
            controller.cancel()
            precondition(controller.state == "idle" && !controller.recordingPanelVisible, "cancel must dismiss \(sessionState)")
        }
        controller.fail("Test failure")
        precondition(controller.state == "error" && controller.recordingPanelVisible && controller.recordingPanelTransparent)
        try await Task.sleep(nanoseconds: 4_300_000_000)
        fputs("dismiss state=\(controller.state) visible=\(controller.recordingPanelVisible) message=\(controller.message)\n", stderr)
        precondition(controller.state == "idle" && !controller.recordingPanelVisible, "errors must dismiss without a view timer")
        controller.refreshRecordingWindow()
        precondition(!controller.recordingPanelVisible, "idle panel must remain hidden")
        withExtendedLifetime(crashing) {}
        print("helper timeout, cancellation, relaunch and capture crash checks passed")
    }
}
