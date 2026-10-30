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
    func begin() throws {
        guard !active else { return }
        do { paused = try controller.pausePlaying(); active = true }
        catch let error as PlayerPauseError { paused = error.paused; active = true; throw error }
    }
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

struct PlayerPauseError: Error { let paused: [String] }

final class PlayerMediaController: MediaControlling {
    private let players: any PlayerControlling
    private let gate: MediaGate
    init(players: any PlayerControlling, gate: MediaGate) { self.players = players; self.gate = gate }
    func pausePlaying() throws -> [String] {
        let running = players.runningPlayers()
        var paused: [String] = []
        var failed = false
        for player in running {
            guard players.authorized(player), let state = players.state(player) else { failed = true; continue }
            if state == "playing" {
                if gate.ifActive({ players.pause(player) }) { paused.append(player) }
                else { failed = true }
                // Retain ownership even if the recording ended while pause was in flight.
                if !gate.operationIsActive() { break }
            }
        }
        if failed { throw PlayerPauseError(paused: paused) }
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
    func operationIsActive() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && generation == operation
    }
    func ifActive(_ action: () -> Bool) -> Bool {
        operationIsActive() && action()
    }
    private func operationIsStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return !active && generation == operation + 1
    }
    func ifStopped(_ action: () -> Bool) -> Bool {
        guard operationIsStopped() else { return false }
        let result = action()
        return operationIsStopped() && result
    }
}
