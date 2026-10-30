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
    func resume(_ players: [String]) -> [String] { resumed.append(players); return [] }
}
let fake = FakeMediaController(["synthetic-player"])
let pause = MediaPauseSession(controller: fake)
try pause.begin(); try pause.begin(); pause.end(); pause.end()
precondition(fake.pauseCalls == 1 && fake.resumed == [["synthetic-player"]])
let alreadyPaused = FakeMediaController([])
let noPlayback = MediaPauseSession(controller: alreadyPaused)
try noPlayback.begin(); noPlayback.end()
precondition(alreadyPaused.resumed.isEmpty)
print("Media pause lifecycle checks passed")
enum FakeMediaError: Error { case denied }
final class DeniedMediaController: MediaControlling {
    var calls = 0
    func pausePlaying() throws -> [String] { calls += 1; throw FakeMediaError.denied }
    func resume(_ players: [String]) -> [String] { preconditionFailure("No player was paused") }
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

final class FakePlayers: PlayerControlling {
    var states: [String: String] = [:]
    var permitted = true
    var failing: Set<String> = []
    var unresponsive: Set<String> = []
    var pauses: [String] = []
    var resumes: [String] = []
    var onState: (() -> Void)?
    var onPause: (() -> Void)?
    func runningPlayers() -> [String] { Array(states.keys) }
    func authorized(_ player: String) -> Bool { permitted }
    func state(_ player: String) -> String? { onState?(); return unresponsive.contains(player) ? nil : states[player] }
    func pause(_ player: String) -> Bool { pauses.append(player); guard !failing.contains(player) else { return false }; states[player] = "paused"; onPause?(); return true }
    var invalidated: Set<String> = []
    func ownershipValid(_ player: String) -> Bool { !invalidated.contains(player) }
    func resume(_ player: String) -> Bool { resumes.append(player); states[player] = "playing"; return true }
}
let players = FakePlayers(), playerGate = MediaGate()
let playerController = PlayerMediaController(players: players, gate: playerGate)
let playerSession = MediaPauseSession(controller: playerController)
func startPlayers() throws { let token = playerGate.start(); playerGate.setOperation(token); try playerSession.begin() }
func stopPlayers() { playerGate.stop(); playerSession.end() }
try startPlayers(); stopPlayers()
precondition(players.pauses.isEmpty && players.resumes.isEmpty)
players.states["music"] = "playing"
try startPlayers(); stopPlayers()
precondition(players.pauses == ["music"] && players.resumes == ["music"])
try startPlayers(); players.states["music"] = "playing"; stopPlayers()
precondition(players.resumes.count == 1)
try startPlayers(); players.states.removeAll(); stopPlayers()
precondition(players.resumes.count == 1)
players.states["music"] = "playing"; players.permitted = false
let deniedToken = playerGate.start(); playerGate.setOperation(deniedToken)
do { try playerSession.begin(); preconditionFailure("Expected permission failure") } catch is PlayerPauseError {}
playerGate.stop(); playerSession.end()
precondition(players.pauses.count == 3 && players.resumes.count == 1)
print("Player permission and lifecycle checks passed")

for unresponsive in [false, true] {
    let failingPlayers = FakePlayers(), failingGate = MediaGate()
    failingPlayers.states = ["good": "playing", "bad": "playing"]
    if unresponsive { failingPlayers.unresponsive.insert("bad") } else { failingPlayers.failing.insert("bad") }
    let session = MediaPauseSession(controller: PlayerMediaController(players: failingPlayers, gate: failingGate))
    let token = failingGate.start(); failingGate.setOperation(token)
    do { try session.begin(); preconditionFailure("Expected fallback") } catch is PlayerPauseError {}
    failingGate.stop(); session.end()
    precondition(failingPlayers.resumes == ["good"])
}
print("Player failures retain ownership for restoration")
let slowGate = MediaGate(), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
let slowToken = slowGate.start(); slowGate.setOperation(slowToken)
DispatchQueue.global().async {
    _ = slowGate.ifActive { entered.signal(); release.wait(); return true }
    done.signal()
}
entered.wait()
let start = Date(); slowGate.stop(); _ = slowGate.start()
precondition(Date().timeIntervalSince(start) < 0.1)
release.signal(); done.wait()
print("Slow player send does not block recording transitions")

// A queued stop can run after the next start; the next stop must restore ownership.
let consecutivePlayers = FakePlayers(), consecutiveGate = MediaGate()
consecutivePlayers.states["music"] = "playing"
let consecutiveSession = MediaPauseSession(controller: PlayerMediaController(players: consecutivePlayers, gate: consecutiveGate))
let one = consecutiveGate.start(); consecutiveGate.setOperation(one); try consecutiveSession.begin()
let stoppedOne = consecutiveGate.stop(); let two = consecutiveGate.start()
consecutiveGate.setOperation(stoppedOne); consecutiveSession.end()
consecutiveGate.setOperation(two); try consecutiveSession.begin()
consecutiveGate.stop(); consecutiveSession.end()
precondition(consecutivePlayers.resumes == ["music"] && consecutivePlayers.states["music"] == "playing")

// A user play/pause invalidates the old claim, even if the final state is paused.
let changedPlayers = FakePlayers(), changedGate = MediaGate()
changedPlayers.states["music"] = "playing"
let changedMediaSession = MediaPauseSession(controller: PlayerMediaController(players: changedPlayers, gate: changedGate))
let changedOne = changedGate.start(); changedGate.setOperation(changedOne); try changedMediaSession.begin()
changedGate.stop(); let changedTwo = changedGate.start(); changedMediaSession.end()
changedPlayers.states["music"] = "playing"; changedPlayers.invalidated.insert("music"); changedPlayers.states["music"] = "paused"
changedGate.setOperation(changedTwo); try changedMediaSession.begin(); changedGate.stop(); changedMediaSession.end()
precondition(changedPlayers.resumes.isEmpty && changedPlayers.states["music"] == "paused")
print("Consecutive sessions preserve ownership and respect user changes")

// Transitions can occur while an Automation state query or pause reply is in flight.
for duringPause in [false, true] {
    let delayedPlayers = FakePlayers(), delayedGate = MediaGate()
    delayedPlayers.states["music"] = "playing"
    let delayedSession = MediaPauseSession(controller: PlayerMediaController(players: delayedPlayers, gate: delayedGate))
    let first = delayedGate.start(); delayedGate.setOperation(first)
    var second = 0
    if duringPause {
        delayedPlayers.onPause = { delayedPlayers.onPause = nil; delayedGate.stop(); second = delayedGate.start() }
        try delayedSession.begin()
        delayedSession.end()
    } else {
        try delayedSession.begin(); delayedGate.stop()
        delayedPlayers.onState = { delayedPlayers.onState = nil; second = delayedGate.start() }
        delayedSession.end()
    }
    delayedGate.setOperation(second); try delayedSession.begin(); delayedGate.stop(); delayedSession.end()
    precondition(delayedPlayers.resumes == ["music"] && delayedPlayers.states["music"] == "playing")
}
print("Slow Automation replies preserve pause ownership")

let playerIntent = PlayerIntentTracker(), musicIdentity = "com.apple.Music|123|1"
playerIntent.begin(musicIdentity)
playerIntent.playbackChanged(bundle: "com.apple.Music", state: "playing") // Queued update preceding our pause.
playerIntent.playbackChanged(bundle: "com.apple.Music", state: "paused")
playerIntent.playbackChanged(bundle: "com.apple.Music", state: "paused") // Duplicate player metadata.
precondition(playerIntent.valid(musicIdentity))
playerIntent.playbackChanged(bundle: "com.apple.Music", state: "playing")
playerIntent.playbackChanged(bundle: "com.apple.Music", state: "paused")
precondition(!playerIntent.valid(musicIdentity))
print("Player notifications distinguish queued updates from user changes")
