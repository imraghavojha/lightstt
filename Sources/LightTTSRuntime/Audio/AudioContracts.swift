import Foundation

public struct DuckingOptions: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case pause, mute, lower, none
    }
    public let mode: Mode
    public let increaseMicrophoneVolume: Bool
    public init(mode: Mode, increaseMicrophoneVolume: Bool) {
        self.mode = mode
        self.increaseMicrophoneVolume = increaseMicrophoneVolume
    }
}

public enum RecordingCue: Equatable, Sendable {
    case start, stop, cancel
}

@MainActor
public protocol AudioDucking: AnyObject {
    func begin(
        session: SessionID, options: DuckingOptions,
        onWarning: @escaping @MainActor @Sendable (String?) -> Void)
    func end(session: SessionID)
    func waitForRestoration() async
}

@MainActor
public protocol RecordingCuePlaying {
    func play(_ cue: RecordingCue)
}
