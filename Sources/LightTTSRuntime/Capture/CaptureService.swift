import Foundation

public enum CaptureServiceError: Error, Equatable {
    case alreadyRecording
}

@MainActor
public final class CaptureService: CaptureServicing {
    private let factory: any CaptureDriverFactory
    private var driver: (any CaptureDriver)?
    private var deviceUID = ""
    private var generation: UInt64 = 0

    public init(factory: any CaptureDriverFactory) {
        self.factory = factory
    }

    public func start(
        deviceUID: String, onLevel: @escaping @MainActor @Sendable (Float) -> Void
    ) throws {
        guard driver == nil else { throw CaptureServiceError.alreadyRecording }
        generation &+= 1
        let currentGeneration = generation
        let newDriver = factory.makeDriver()
        driver = newDriver
        self.deviceUID = deviceUID
        do {
            try newDriver.start(deviceUID: deviceUID) { [weak self] level in
                Task { @MainActor [weak self] in
                    guard let self, self.driver != nil, self.generation == currentGeneration else {
                        return
                    }
                    onLevel(level)
                }
            }
        } catch {
            driver = nil
            generation &+= 1
            throw error
        }
    }

    public func stop() -> CapturedAudio? {
        guard let driver else { return nil }
        self.driver = nil
        generation &+= 1
        return CapturedAudio(pcm: driver.stop(), deviceUID: deviceUID, driver: driver)
    }

    public func cancel() {
        guard let driver else { return }
        self.driver = nil
        generation &+= 1
        _ = driver.stop()
    }
}
