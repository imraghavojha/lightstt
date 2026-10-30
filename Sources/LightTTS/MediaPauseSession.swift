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

struct ActivityGatedMediaController: MediaControlling {
    let isOutputRunning: () -> Bool
    let toggle: () -> Void
    func pausePlaying() throws -> [String] { guard isOutputRunning() else { return [] }; toggle(); return ["system"] }
    func resume(_ players: [String]) { if !players.isEmpty { toggle() } }
}
