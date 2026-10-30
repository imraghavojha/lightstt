import Foundation

extension ModelResidencyPolicy {
    /// The idle action follows the existing power and keep-loaded preference behavior.
    public func idleUnloadDelay(for phase: RecordingPhase) -> TimeInterval? {
        switch phase {
        case .starting, .recording, .processing:
            return nil
        case .idle, .done, .error:
            guard !onACPower else { return nil }
            return keepLoaded ? max(1, unloadAfter) : 0
        }
    }
}
