import Foundation

/// Tracks the original clipboard across consecutive pastes while we still own it.
public final class PasteRestoration<Snapshot> {
    private var pending: (count: Int, snapshot: Snapshot)?

    public init() {}

    public func original(currentCount: Int, capture: () -> Snapshot) -> Snapshot {
        if let pending, pending.count == currentCount { return pending.snapshot }
        pending = nil
        return capture()
    }

    public func published(count: Int, original: Snapshot, restore: Bool) {
        pending = restore ? (count, original) : nil
    }

    public func takeForRestore(expectedCount: Int, currentCount: Int) -> Snapshot? {
        guard let pending, pending.count == expectedCount else { return nil }
        self.pending = nil
        return currentCount == expectedCount ? pending.snapshot : nil
    }
}
