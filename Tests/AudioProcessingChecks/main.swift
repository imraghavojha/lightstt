import Foundation
precondition(AudioProcessing.recordingError(samples: [], duration: 0.1, pushToTalk: true)?.contains("delivered no audio") == true)
precondition(AudioProcessing.recordingError(samples: [0, 0], duration: 2, pushToTalk: false)?.contains("input is silent") == true)
precondition(AudioProcessing.recordingError(samples: [0.01], duration: 0.1, pushToTalk: true)?.contains("too short") == true)
precondition(AudioProcessing.recordingError(samples: [0.01], duration: 0.1, pushToTalk: false)?.contains("too short") == true)
precondition(AudioProcessing.recordingError(samples: [0.00001], duration: 2, pushToTalk: false) == nil)
precondition(AudioProcessing.apply([Float](repeating: 0.00001, count: 16000), removeSilence: true, normalize: false).isEmpty)
let input = [Float](repeating: 0, count: 16000) + [Float](repeating: 0.05, count: 3200) + [Float](repeating: 0, count: 16000)
let trimmed = AudioProcessing.apply(input, removeSilence: true, normalize: false)
precondition(trimmed.count < input.count && trimmed.contains(0.05) && trimmed.count > 3200)
let normalized = AudioProcessing.apply([Float](repeating: 0.05, count: 16000), removeSilence: false, normalize: true)
precondition(abs(normalized[0] - 0.12) < 0.001)
precondition(AudioProcessing.apply([], removeSilence: true, normalize: true).isEmpty)
print("Audio processing checks passed")
final class FakeMediaController: MediaControlling {
    var currentlyPlaying: [String]
    var pauseCalls = 0
    var resumed: [[String]] = []
    init(_ playing: [String]) { currentlyPlaying = playing }
    func pausePlaying() throws -> [String] { pauseCalls += 1; return currentlyPlaying }
    func resume(_ players: [String]) { resumed.append(players) }
}
let fake = FakeMediaController(["synthetic-player"])
let pause = MediaPauseSession(controller: fake)
try pause.begin(); try pause.begin(); pause.end(); pause.end()
precondition(fake.pauseCalls == 1 && fake.resumed == [["synthetic-player"]])
let alreadyPaused = FakeMediaController([])
let noPlayback = MediaPauseSession(controller: alreadyPaused)
try noPlayback.begin(); noPlayback.end()
precondition(alreadyPaused.resumed == [[]])
print("Media pause lifecycle checks passed")
enum FakeMediaError: Error { case denied }
final class DeniedMediaController: MediaControlling {
    var calls = 0
    func pausePlaying() throws -> [String] { calls += 1; throw FakeMediaError.denied }
    func resume(_ players: [String]) { preconditionFailure("No player was paused") }
}
let denied = DeniedMediaController()
let deniedSession = MediaPauseSession(controller: denied)
for _ in 0..<2 { do { try deniedSession.begin(); preconditionFailure("Expected failure") } catch FakeMediaError.denied {} }
deniedSession.end()
precondition(denied.calls == 2)
print("Media failure handling checks passed")
let safeSession = MediaPauseSession(controller: NoopMediaController())
try safeSession.begin(); safeSession.end()
print("Unknown media state is left alone")
let twoPhrases = [Float](repeating: 0, count: 16000) + [Float](repeating: 0.08, count: 3200) + [Float](repeating: 0, count: 16000) + [Float](repeating: 0.08, count: 3200)
let segments = AudioProcessing.speechSegments(twoPhrases)
precondition(segments.count == 2 && segments[0].start < 1 && segments[0].end < segments[1].start && segments[1].end <= Double(twoPhrases.count) / 16000)
precondition(AudioProcessing.speechSegments([Float](repeating: 0, count: 1000)).isEmpty)
print("Speech segmentation checks passed")
precondition(AudioProcessing.waveform([]).isEmpty)
let waveform = AudioProcessing.waveform([Float](repeating: 0.05, count: 3200), bins: 10)
precondition(waveform.count == 10 && waveform.allSatisfy { $0 > 0 && $0 <= 1 })
print("Waveform checks passed")
final class FakeVolume: OutputVolumeControlling {
    var values: [UInt32: Float] = [1: 0.8, 2: 0.4]
    var quantize = false
    func volumes() -> [(UInt32, Float)] { values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) } }
    func setVolume(_ value: Float, channel: UInt32) { values[channel] = quantize ? (value * 10).rounded() / 10 : value }
}
for factor: Float in [0, 0.3] {
    let output = FakeVolume(), session = OutputVolumeSession(controller: output)
    session.begin(factor: factor); session.begin(factor: factor)
    precondition(abs(output.values[1]! - 0.8 * factor) < 0.0001 && abs(output.values[2]! - 0.4 * factor) < 0.0001)
    session.end(); session.end()
    precondition(output.values[1] == 0.8 && output.values[2] == 0.4)
}
print("Output volume restoration checks passed")

let changedOutput = FakeVolume(), changedSession = OutputVolumeSession(controller: changedOutput)
changedSession.begin(factor: 0.3); changedOutput.values[1] = 0.5; changedSession.end()
precondition(changedOutput.values[1] == 0.5 && changedOutput.values[2] == 0.4)
let quantizedOutput = FakeVolume(), quantizedSession = OutputVolumeSession(controller: quantizedOutput)
quantizedSession.begin(factor: 0.3)
quantizedOutput.values[1] = 0.25 // A small deliberate change from 0.24 must survive.
quantizedSession.end()
precondition(quantizedOutput.values[1] == 0.25 && quantizedOutput.values[2] == 0.4)
print("Output user adjustment checks passed")
let device = FakeVolume(), deviceSession = OutputVolumeSession(controller: device)
device.quantize = true
deviceSession.begin(factor: 0.3)
precondition(device.values[1] == 0.2)
deviceSession.end()
precondition(device.values[1] == 0.8 && device.values[2] == 0.4)
print("Quantized readback restoration checks passed")
let gate = MediaGate()
let first = gate.start(); gate.setOperation(first); gate.stop()
precondition(gate.ifStopped { true })
gate.stop() // A stop followed by an error must not invalidate restoration.
precondition(gate.ifStopped { true })
_ = gate.start()
var sent = false
precondition(!gate.ifStopped { sent = true; return true } && !sent)
print("New recording blocks pending media resume")

let intent = MediaIntentTracker()
intent.begin(); intent.playbackChanged(false)
precondition(intent.finish { true })
intent.begin(); intent.playbackChanged(false); intent.playbackChanged(true); intent.playbackChanged(false)
precondition(!intent.finish { true })
intent.begin(); intent.playbackChanged(false); intent.playerChanged()
precondition(!intent.finish { true })
intent.begin()
precondition(!intent.finish { true })
print("Media intent changes prevent automatic resume")
