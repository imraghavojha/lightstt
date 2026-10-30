import Foundation

/// Used from a serial queue; failed recordings remain available for the next save.
public final class HistoryPersistence {
    public typealias Writer = (_ data: Data, _ url: URL) throws -> Void
    private let writer: Writer
    private var pending: [String: Data] = [:]

    public init(
        writer: @escaping Writer = { data, url in
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.writer = writer
    }

    public func enqueueRecording(_ data: Data, named name: String) {
        pending[name] = data
    }

    public func save(_ history: Data, in folder: URL, fallback: URL?) -> (
        folder: URL, fellBack: Bool, error: Error?
    ) {
        do {
            if fallback != nil && !FileManager.default.fileExists(atPath: folder.path) {
                throw CocoaError(.fileNoSuchFile)
            }
            try write(history, in: folder)
            return (folder, false, nil)
        } catch {
            guard let fallback, fallback != folder else { return (folder, false, error) }
            do {
                try write(history, in: fallback)
                return (fallback, true, nil)
            } catch {
                return (fallback, true, error)
            }
        }
    }

    private func write(_ history: Data, in folder: URL) throws {
        for (name, data) in pending {
            try writer(
                data,
                folder.appendingPathComponent("Recordings", isDirectory: true)
                    .appendingPathComponent(name))
        }
        try writer(history, folder.appendingPathComponent("history.json"))
        pending.removeAll()
    }
}
