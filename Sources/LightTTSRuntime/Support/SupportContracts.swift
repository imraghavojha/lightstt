import Foundation

public struct RecordingStartOptions: Equatable, Sendable {
    public let deviceUID: String
    public let autoPaste: Bool
    public init(deviceUID: String, autoPaste: Bool) {
        self.deviceUID = deviceUID
        self.autoPaste = autoPaste
    }
}

public struct AudioProcessingOptions: Equatable, Sendable {
    public let removeSilence: Bool
    public let normalize: Bool
    public init(removeSilence: Bool, normalize: Bool) {
        self.removeSilence = removeSilence
        self.normalize = normalize
    }
}

public struct InsertionOptions: Equatable, Sendable {
    public let simulateTyping: Bool
    public let sendOnShift: Bool
    public let restoreClipboard: Bool
    public let allowClipboardHistory: Bool
    public init(
        simulateTyping: Bool, sendOnShift: Bool, restoreClipboard: Bool, allowClipboardHistory: Bool
    ) {
        self.simulateTyping = simulateTyping
        self.sendOnShift = sendOnShift
        self.restoreClipboard = restoreClipboard
        self.allowClipboardHistory = allowClipboardHistory
    }
}

/// Read each group at the point in the workflow where it is currently sampled.
@MainActor
public protocol RecordingPreferencesReading {
    func startOptions() -> RecordingStartOptions
    func modelSelection() -> EngineConfiguration
    func audioProcessingOptions() -> AudioProcessingOptions
    func insertionOptions() -> InsertionOptions
    func residencyPolicy() -> ModelResidencyPolicy
}

@MainActor
public protocol ScheduledCancellation {
    func cancel()
}

@MainActor
public protocol RuntimeScheduling {
    var wallTime: Date { get }
    var monotonicTime: TimeInterval { get }
    @discardableResult
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)
        -> any ScheduledCancellation
}

public protocol TraceSink {
    func mark(_ stage: String)
}
