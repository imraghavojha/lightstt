import Foundation
import CryptoKit

final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let resumeURL: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var staged: URL?
    private var failure: Error?
    private var cancelled = false
    init(resumeURL: URL, progress: @escaping @Sendable (Double) -> Void) { self.resumeURL = resumeURL; self.progress = progress }
    func run(url: URL) async throws -> URL {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
                let resume = try? Data(contentsOf: resumeURL)
                let download = resume.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
                task = download; download.resume(); lock.unlock()
            }
        }, onCancel: { self.cancel() })
    }
    private func cancel() {
        lock.lock(); cancelled = true; let current = continuation == nil ? nil : task; lock.unlock()
        current?.cancel { [self] data in
            if let data { try? data.write(to: resumeURL, options: .atomic) }
            lock.lock(); let continuation = self.continuation; self.continuation = nil; lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.url?.scheme?.lowercased() == "https" else { throw SpeechError.model("Download failed or redirected to an insecure URL") }
            let target = resumeURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".download")
            try FileManager.default.moveItem(at: location, to: target); staged = target
        } catch { failure = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let isCancelled = cancelled; let continuation = isCancelled ? nil : self.continuation; if !isCancelled { self.continuation = nil }; lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if isCancelled { if let staged { try? FileManager.default.removeItem(at: staged) }; return }
        if let error = failure ?? error { try? FileManager.default.removeItem(at: resumeURL); continuation?.resume(throwing: error); return }
        guard let staged else { continuation?.resume(throwing: SpeechError.model("Download did not finish")); return }
        try? FileManager.default.removeItem(at: resumeURL); continuation?.resume(returning: staged)
    }
}

public enum ModelValidation {
    public static func verify(_ url: URL, sha256: String?, size: Int64?) throws {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        guard try file.read(upToCount: 4) == Data([0x6c, 0x6d, 0x67, 0x67]) else { throw SpeechError.model("Not a whisper.cpp GGML model") }
        try file.seek(toOffset: 0)
        var hash = SHA256(); var count: Int64 = 0
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk); count += Int64(chunk.count) }
        if let size, size != count { throw SpeechError.model("Model size does not match catalog") }
        if let sha256, hash.finalize().map({ String(format: "%02x", $0) }).joined() != sha256.lowercased() { throw SpeechError.model("Model SHA-256 does not match") }
    }
}
