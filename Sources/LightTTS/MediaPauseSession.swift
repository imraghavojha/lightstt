import Foundation

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
    func stop() { lock.lock(); generation += 1; active = false; lock.unlock() }
    func isCurrent(_ token: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return active && generation == token }
    func ifActive(_ action: () -> Bool) -> Bool { lock.lock(); defer { lock.unlock() }; return active && generation == operation && action() }
    func ifStopped(_ action: () -> Bool) -> Bool { lock.lock(); defer { lock.unlock() }; return !active && generation == operation + 1 && action() }
}
