import Foundation

/// Opt-in timings measure AppKit calls and SwiftUI state delivery, not screen presentation.
@MainActor enum UITrace {
    private static let enabled = ProcessInfo.processInfo.environment["LIGHTTTS_TRACE"] == "1"
    private static var starts: [String: TimeInterval] = [:]
    static func begin(_ name: String) { if enabled { starts[name] = ProcessInfo.processInfo.systemUptime } }
    static func end(_ name: String) { if let start = starts.removeValue(forKey: name) { duration(name, since: start) } }
    static func duration(_ name: String, since start: TimeInterval) {
        guard enabled else { return }
        NSLog("LIGHTTTS_TRACE %@ %.2f ms", name, (ProcessInfo.processInfo.systemUptime - start) * 1000)
    }
}
