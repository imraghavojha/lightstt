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
        previous = controller.volumes().map { (channel: $0.0, original: $0.1, applied: $0.1 * factor) }
        for entry in previous { controller.setVolume(entry.applied, channel: entry.channel) }
    }
    func end() {
        let current = Dictionary(uniqueKeysWithValues: controller.volumes())
        for entry in previous where current[entry.channel] == entry.applied { controller.setVolume(entry.original, channel: entry.channel) }
        previous = []
    }
}
