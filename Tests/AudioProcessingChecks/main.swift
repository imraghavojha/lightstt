import Foundation
let input = [Float](repeating: 0, count: 16000) + [Float](repeating: 0.05, count: 3200) + [Float](repeating: 0, count: 16000)
let trimmed = AudioProcessing.apply(input, removeSilence: true, normalize: false)
precondition(trimmed.count < input.count && trimmed.contains(0.05) && trimmed.count > 3200)
let normalized = AudioProcessing.apply([Float](repeating: 0.05, count: 16000), removeSilence: false, normalize: true)
precondition(abs(normalized[0] - 0.12) < 0.001)
precondition(AudioProcessing.apply([], removeSilence: true, normalize: true).isEmpty)
print("Audio processing checks passed")
func filteredRMS(frequency: Float) -> Float {
    let frames = 4800
    var signal = (0..<frames).flatMap { i -> [Float] in let v = sin(2 * Float.pi * frequency * Float(i) / 48000); return [v, v] }
    var filter = StereoLowPass(); filter.prepare(sampleRate: 48000)
    signal.withUnsafeMutableBufferPointer { filter.process($0.baseAddress!, frameCount: frames, channelCount: 2) }
    return sqrt(signal.reduce(Float.zero) { $0 + $1 * $1 } / Float(signal.count))
}
precondition(filteredRMS(frequency: 5000) < filteredRMS(frequency: 100) * 0.3)
print("Muffle filter check passed")
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
