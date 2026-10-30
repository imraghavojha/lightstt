import Foundation

/// Each subscription yields the current snapshot first and removes itself on termination.
@MainActor
public protocol StateSource: AnyObject {
    associatedtype Snapshot
    var snapshot: Snapshot { get }
    func snapshots() -> AsyncStream<Snapshot>
}

public struct SessionID: Hashable, Sendable {
    public let generation: UInt64
    public init(generation: UInt64) {
        self.generation = generation
    }
}

public struct SessionFailure: Error, Equatable, Sendable {
    public enum Category: Equatable, Sendable {
        case permission, capture, transcription, insertion, other
    }
    public let category: Category
    public let message: String
    public init(category: Category, message: String) {
        self.category = category
        self.message = message
    }
}

public enum ProcessingStage: Equatable, Sendable {
    case loadingModel, transcribing, savingHistory
}

public enum RecordingPhase: Equatable, Sendable {
    case idle, starting, recording
    case processing(ProcessingStage)
    case done
    case error(SessionFailure)
}

public enum RecordingTrigger: Equatable, Sendable {
    case toggle, pushToTalk, mouse
}

public struct RecordingSnapshot: Equatable, Sendable {
    public let phase: RecordingPhase
    public let sessionID: SessionID?
    public let startDate: Date?
    public let message: String?
    public init(phase: RecordingPhase, sessionID: SessionID?, startDate: Date?, message: String?) {
        self.phase = phase
        self.sessionID = sessionID
        self.startDate = startDate
        self.message = message
    }
}

@MainActor
public protocol RecordingControlling: StateSource where Snapshot == RecordingSnapshot {
    func start(trigger: RecordingTrigger)
    func stop()
    func cancel()
    func dismissResult()
    func beginShutdown()
    func finishShutdown() async
}
