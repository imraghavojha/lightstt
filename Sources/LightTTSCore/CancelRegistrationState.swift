/// Tracks whether cancellation should be available while the monitor is installed.
public struct CancelRegistrationState {
    public private(set) var recording = false
    public private(set) var installed = false
    public init() {}
    public static func isActiveSession(_ state: String) -> Bool {
        ["starting", "recording", "processing", "loading"].contains(state)
    }
    public var shouldRegister: Bool { recording && installed }
    public mutating func setRecording(_ value: Bool) { recording = value }
    public mutating func setInstalled(_ value: Bool) { installed = value }
}
