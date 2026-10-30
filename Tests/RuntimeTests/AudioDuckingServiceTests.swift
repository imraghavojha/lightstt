import LightTTSRuntime
import XCTest

@MainActor
private final class DuckingFake: AudioDuckingDriver {
    var options: [DuckingOptions] = []
    var callbacks: [@Sendable (String?) -> Void] = []
    var endCount = 0
    var pendingResume = false
    var resumeCount = 0
    var flush: CheckedContinuation<Void, Never>?

    func begin(options: DuckingOptions, completion: @escaping @Sendable (String?) -> Void) {
        pendingResume = false
        self.options.append(options)
        callbacks.append(completion)
    }

    func end() {
        endCount += 1
        pendingResume = true
    }

    func completeResume() {
        if pendingResume { resumeCount += 1 }
        pendingResume = false
        flush?.resume()
        flush = nil
    }

    func waitForRestoration() async {
        if pendingResume {
            await withCheckedContinuation { flush = $0 }
        }
    }
}

@MainActor
final class AudioDuckingServiceTests: XCTestCase {
    private let options = DuckingOptions(mode: .pause, increaseMicrophoneVolume: true)
    private func session(_ generation: UInt64) -> SessionID { SessionID(generation: generation) }

    func testEndBeforeBeginAndRepeatedEnd() {
        let driver = DuckingFake()
        let service = AudioDuckingService(driver: driver)
        service.end(session: session(1))
        service.begin(session: session(1), options: options) { _ in XCTFail("late warning") }
        XCTAssertTrue(driver.options.isEmpty)
        service.begin(session: session(2), options: options) { _ in }
        service.begin(session: session(2), options: options) { _ in }
        service.end(session: session(1))
        XCTAssertEqual(driver.endCount, 0)
        service.end(session: session(2))
        service.end(session: session(2))
        XCTAssertEqual(driver.options, [options])
        XCTAssertEqual(driver.endCount, 1)
        driver.completeResume()
        driver.completeResume()
        XCTAssertEqual(driver.resumeCount, 1)
    }

    func testNewSessionInvalidatesPendingResumeAndOldEnd() {
        let driver = DuckingFake()
        let service = AudioDuckingService(driver: driver)
        service.begin(session: session(1), options: options) { _ in }
        service.end(session: session(1))
        service.begin(session: session(2), options: options) { _ in }
        service.end(session: session(1))
        driver.completeResume()
        XCTAssertEqual(driver.resumeCount, 0)
        XCTAssertEqual(driver.endCount, 1)
        service.end(session: session(2))
        driver.completeResume()
        XCTAssertEqual(driver.resumeCount, 1)
    }

    func testNewBeginEndsPreviousSession() {
        let driver = DuckingFake()
        let service = AudioDuckingService(driver: driver)
        service.begin(session: session(1), options: options) { _ in }
        service.begin(session: session(2), options: options) { _ in }
        XCTAssertEqual(driver.endCount, 1)
        XCTAssertFalse(driver.pendingResume)
        service.end(session: session(3))
        service.begin(session: session(3), options: options) { _ in }
        XCTAssertEqual(driver.endCount, 2)
        XCTAssertEqual(driver.options.count, 2)
    }

    func testLateWarningsAreDropped() async {
        let driver = DuckingFake()
        let service = AudioDuckingService(driver: driver)
        let delivered = expectation(description: "current warning")
        var warnings: [String] = []
        service.begin(session: session(1), options: options) { warning in
            warnings.append(warning ?? "nil")
        }
        driver.callbacks[0]("queued before end")
        service.end(session: session(1))
        service.begin(session: session(2), options: options) { warning in
            warnings.append(warning ?? "nil")
            delivered.fulfill()
        }
        driver.callbacks[0]("late")
        driver.callbacks[1]("current")
        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(warnings, ["current"])
    }

    func testWaitForRestorationFlushesPendingWork() async {
        let driver = DuckingFake()
        let service = AudioDuckingService(driver: driver)
        service.begin(session: session(1), options: options) { _ in }
        service.end(session: session(1))
        let waiting = expectation(description: "waiting for restoration")
        let finished = expectation(description: "restoration finished")
        let task = Task { @MainActor in
            waiting.fulfill()
            await service.waitForRestoration()
            finished.fulfill()
        }
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertNotNil(driver.flush)
        driver.completeResume()
        await fulfillment(of: [finished], timeout: 1)
        await task.value
        await service.waitForRestoration()
        XCTAssertEqual(driver.resumeCount, 1)
    }
}
