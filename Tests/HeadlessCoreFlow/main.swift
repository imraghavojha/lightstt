import AVFoundation
import Foundation
import LightTTSCore

// The fixture branch of AudioCapture never accesses an input device.
enum InputDevice { static func applySelection(to engine: AVAudioEngine) throws { fatalError("Unexpected microphone path") } }
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
let args = CommandLine.arguments
let converted = try AudioFileReader.read(URL(fileURLWithPath: args[1]))
check(converted.count > 8000, "file conversion must produce >0.5 seconds at 16 kHz")
check(converted.contains { abs($0) > 0.001 }, "converted audio is not silent")
try converted.withUnsafeBytes { try Data($0).write(to: URL(fileURLWithPath: args[2])) }
print("PASS: AudioFileReader converts generated speech to 16 kHz mono float PCM (\(converted.count) samples)")
let expected = try AudioFileReader.read(URL(fileURLWithPath: ProcessInfo.processInfo.environment["LIGHTTTS_TEST_AUDIO"]!))
let capture = AudioCapture { _ in }
try capture.start()
Thread.sleep(forTimeInterval: Double(expected.count) / 16000 + 0.25)
let captured = capture.stop()
check(!capture.isActive && captured.count == expected.count, "fixture capture must read all frames and stop")
check(zip(captured, expected).allSatisfy { abs($0 - $1) < 0.00001 }, "fixture capture samples")
print("PASS: LIGHTTTS_TEST_AUDIO capture reads the generated 16 kHz mono fixture")
var actions: [String] = []
func insert(_ text: String) throws { actions.append("insert:" + text) }
func type(_ text: String) throws { actions.append("type:" + text) }
func send() throws { actions.append("return") }
try performTextInput("hello", simulateTyping: false, sendOnShift: true, shiftHeld: true, insert: insert, type: type, sendReturn: send)
check(actions == ["insert:hello", "return"], "insert and shift return")
actions = []
try performTextInput("hello", simulateTyping: true, sendOnShift: true, shiftHeld: false, insert: insert, type: type, sendReturn: send)
check(actions == ["type:hello"], "typing without return")
check(shouldCopyTranscript(autoPaste: false, restoreClipboard: true), "copy when autopaste disabled")
check(shouldCopyTranscript(autoPaste: true, restoreClipboard: false), "copy when restore disabled")
check(!shouldCopyTranscript(autoPaste: true, restoreClipboard: true), "no extra copy when restoring")
print("PASS: text input dispatch and existing copy policy")
