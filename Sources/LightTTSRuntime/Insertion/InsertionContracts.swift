import Foundation

public protocol TextTarget: AnyObject, Sendable {
    func paste(_ text: String, restoreClipboard: Bool, allowClipboardHistory: Bool) throws
    func sendReturn() throws
}

public struct FocusResult: Sendable {
    public let target: (any TextTarget)?
    public let disposition: FocusDisposition
    public init(target: (any TextTarget)?, disposition: FocusDisposition) {
        self.target = target
        self.disposition = disposition
    }
}

/// A stop-time capture that can complete asynchronously.
@MainActor
public struct FocusTicket {
    private let resolve: @MainActor () async -> FocusResult
    public init(resolve: @escaping @MainActor () async -> FocusResult) {
        self.resolve = resolve
    }
    public func result() async -> FocusResult {
        await resolve()
    }
}

public struct InsertionOutcome: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        case delivered, copied, skipped
    }
    public let delivery: Delivery
    public let warning: String?
    public init(delivery: Delivery, warning: String? = nil) {
        self.delivery = delivery
        self.warning = warning
    }
}

@MainActor
public protocol InsertionServicing: AnyObject {
    func captureAtStop() -> FocusTicket
    func deliver(
        _ text: String, to focus: FocusTicket, autoPaste: Bool,
        isCurrent: @escaping @MainActor () -> Bool
    ) async -> InsertionOutcome
}

@MainActor
public protocol FocusCapturing {
    func captureAtStop() -> FocusTicket
}

@MainActor
public protocol TranscriptClipboard {
    func write(_ text: String, allowClipboardHistory: Bool)
}
