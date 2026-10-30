import Foundation

/// A resume is safe only after observing our pause and no subsequent player change.
final class MediaIntentTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var awaitingPause = false
    private var valid = false
    func begin() { lock.lock(); awaitingPause = true; valid = true; lock.unlock() }
    func playbackChanged(_ playing: Bool?) {
        lock.lock(); defer { lock.unlock() }
        guard valid else { return }
        if awaitingPause && playing == false { awaitingPause = false }
        else { valid = false }
    }
    func playerChanged() { lock.lock(); valid = false; lock.unlock() }
    func finish(_ action: () -> Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let allowed = valid && !awaitingPause
        valid = false; awaitingPause = false
        return allowed && action()
    }
    func cancel() { lock.lock(); valid = false; awaitingPause = false; lock.unlock() }
}

protocol MediaControlling {
    func pausePlaying() throws -> [String]
    func resume(_ players: [String])
}

final class MediaPauseSession {
    private let controller: any MediaControlling
    private var paused: [String] = []
    private var active = false
    init(controller: any MediaControlling) { self.controller = controller }
    func begin() throws { guard !active else { return }; paused = try controller.pausePlaying(); active = true }
    func end() { guard active else { return }; active = false; controller.resume(paused); paused.removeAll() }
}

struct NoopMediaController: MediaControlling {
    func pausePlaying() throws -> [String] { [] }
    func resume(_ players: [String]) {}
}

/// Player operations are serialized by AudioSettings' session queue.
protocol PlayerControlling {
    func runningPlayers() -> [String]
    func authorized(_ player: String) -> Bool
    func state(_ player: String) -> String?
    func pause(_ player: String) -> Bool
    func resume(_ player: String)
}

enum PlayerPermissionError: Error { case missing }

final class PlayerMediaController: MediaControlling {
    private let players: any PlayerControlling
    private let gate: MediaGate
    init(players: any PlayerControlling, gate: MediaGate) { self.players = players; self.gate = gate }
    func pausePlaying() throws -> [String] {
        let running = players.runningPlayers()
        guard running.allSatisfy({ players.authorized($0) }) else { throw PlayerPermissionError.missing }
        var paused: [String] = []
        for player in running where players.state(player) == "playing" {
            if gate.ifActive({ players.pause(player) }) { paused.append(player) }
        }
        return paused
    }
    func resume(_ paused: [String]) {
        for player in paused where players.runningPlayers().contains(player) && players.authorized(player) && players.state(player) == "paused" {
            _ = gate.ifStopped { players.resume(player); return true }
        }
    }
}

protocol OutputVolumeControlling {
    func volumes() -> [(UInt32, Float)]
    func setVolume(_ value: Float, channel: UInt32)
}
final class OutputVolumeSession {
    private let controller: any OutputVolumeControlling
    private var previous: [(channel: UInt32, original: Float, applied: Float)] = []
    init(controller: any OutputVolumeControlling) { self.controller = controller }
    func begin(factor: Float) {
        guard previous.isEmpty else { return }
        let originals = controller.volumes()
        for (channel, value) in originals { controller.setVolume(value * factor, channel: channel) }
        let readback = Dictionary(uniqueKeysWithValues: controller.volumes())
        previous = originals.compactMap { channel, original in readback[channel].map { (channel, original, $0) } }
    }
    func end() {
        let current = Dictionary(uniqueKeysWithValues: controller.volumes())
        for entry in previous where current[entry.channel].map({ abs($0 - entry.applied) < 0.001 }) == true { controller.setVolume(entry.original, channel: entry.channel) }
        previous = []
    }
}

final class MediaGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var active = false
    private var operation = 0
    func setOperation(_ token: Int) { lock.lock(); operation = token; lock.unlock() }
    func start() -> Int { lock.lock(); defer { lock.unlock() }; generation += 1; active = true; return generation }
    func stop() { lock.lock(); if active { generation += 1; active = false }; lock.unlock() }
    func isCurrent(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return active && generation == token }
    func ifActive(_ action: () -> Bool) -> Bool { lock.lock(); defer { lock.unlock() }; return active && generation == operation && action() }
    func ifStopped(_ action: () -> Bool) -> Bool { lock.lock(); defer { lock.unlock() }; return !active && generation == operation + 1 && action() }
}
