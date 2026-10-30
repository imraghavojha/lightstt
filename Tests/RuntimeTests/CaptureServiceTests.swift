import LightTTSRuntime
import XCTest

@MainActor
private final class CaptureFakeDriver: CaptureDriver {
    enum Failure: Error { case start }
    var receivedUID: String?
    var level: (@Sendable (Float) -> Void)?
    var stopCount = 0
    var shouldFail = false

    func start(deviceUID: String, onLevel: @escaping @Sendable (Float) -> Void) throws {
        receivedUID = deviceUID
        level = onLevel
        if shouldFail { throw Failure.start }
    }

    func stop() -> PCM16k {
        stopCount += 1
        return PCM16k(samples: [0.25, -0.5])
    }
}

@MainActor
private final class CaptureFakeFactory: CaptureDriverFactory {
    var next: CaptureFakeDriver?
    weak var last: CaptureFakeDriver?

    func makeDriver() -> any CaptureDriver {
        let driver = next ?? CaptureFakeDriver()
        next = nil
        last = driver
        return driver
    }
}

@MainActor
final class CaptureServiceTests: XCTestCase {
    func testDeviceStopAndDriverLifetime() throws {
        let factory = CaptureFakeFactory()
        let service = CaptureService(factory: factory)
        try service.start(deviceUID: "microphone", onLevel: { _ in })
        XCTAssertEqual(factory.last?.receivedUID, "microphone")
        weak let driver = factory.last
        var audio = service.stop()
        XCTAssertEqual(audio?.deviceUID, "microphone")
        XCTAssertEqual(audio?.pcm.samples, [0.25, -0.5])
        XCTAssertEqual(driver?.stopCount, 1)
        XCTAssertNil(service.stop())
        service.cancel()
        XCTAssertNotNil(driver)
        audio = nil
        XCTAssertNil(driver)
    }

    func testStartFailureAndRetry() throws {
        let factory = CaptureFakeFactory()
        let failed = CaptureFakeDriver()
        failed.shouldFail = true
        factory.next = failed
        let service = CaptureService(factory: factory)
        XCTAssertThrowsError(try service.start(deviceUID: "bad", onLevel: { _ in }))
        XCTAssertNil(service.stop())
        try service.start(deviceUID: "good", onLevel: { _ in })
        XCTAssertEqual(factory.last?.receivedUID, "good")
        XCTAssertThrowsError(try service.start(deviceUID: "other", onLevel: { _ in }))
        service.cancel()
    }

    func testCancelIsIdempotent() throws {
        let factory = CaptureFakeFactory()
        let driver = CaptureFakeDriver()
        factory.next = driver
        let service = CaptureService(factory: factory)
        try service.start(deviceUID: "", onLevel: { _ in })
        service.cancel()
        service.cancel()
        XCTAssertNil(service.stop())
        XCTAssertEqual(driver.stopCount, 1)
    }

    func testLevelsAndLateLevels() async throws {
        let scheduler = ManualScheduler()
        let factory = CaptureFakeFactory()
        let driver = CaptureFakeDriver()
        factory.next = driver
        let service = CaptureService(factory: factory)
        let delivered = expectation(description: "level delivered")
        var levels: [Float] = []
        try service.start(deviceUID: "first") { level in
            levels.append(level)
            delivered.fulfill()
        }
        _ = scheduler.schedule(after: 1) { driver.level?(0.5) }
        scheduler.advance(by: 1)
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(levels, [0.5])
        driver.level?(0.75)
        _ = service.stop()
        try service.start(deviceUID: "second", onLevel: { _ in })
        await Task.yield()
        XCTAssertEqual(levels, [0.5])
        service.cancel()
    }
}
