import Foundation

public struct PCM16k: Equatable, Sendable {
    public static let sampleRate = 16_000
    public let samples: [Float]
    public init(samples: [Float]) {
        self.samples = samples
    }
}

/// Retains the stopped driver until processing has finished.
@MainActor
public final class CapturedAudio {
    public let pcm: PCM16k
    public let deviceUID: String
    public let driver: any CaptureDriver
    public init(pcm: PCM16k, deviceUID: String, driver: any CaptureDriver) {
        self.pcm = pcm
        self.deviceUID = deviceUID
        self.driver = driver
    }
}

@MainActor
public protocol CaptureServicing: AnyObject {
    func start(deviceUID: String, onLevel: @escaping @MainActor @Sendable (Float) -> Void) throws
    func stop() -> CapturedAudio?
    func cancel()
}

@MainActor
public protocol CaptureDriver: AnyObject {
    func start(deviceUID: String, onLevel: @escaping @Sendable (Float) -> Void) throws
    func stop() -> PCM16k
}

@MainActor
public protocol CaptureDriverFactory {
    func makeDriver() -> any CaptureDriver
}
