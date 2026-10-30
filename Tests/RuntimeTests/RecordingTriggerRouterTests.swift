import Foundation
import LightTTSRuntime
import XCTest

@MainActor
private final class RouterRecording: RecordingControlling {
    var snapshot = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    var generation: UInt64 = 0
    var stops = 0
    var cancels = 0
    func snapshots() -> AsyncStream<RecordingSnapshot> { AsyncStream { $0.finish() } }
    func start(trigger: RecordingTrigger) {
        generation += 1
        snapshot = RecordingSnapshot(
            phase: .recording, sessionID: SessionID(generation: generation), startDate: nil,
            message: nil)
    }
    func stop() {
        stops += 1
        snapshot = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    }
    func cancel() {
        cancels += 1
        snapshot = RecordingSnapshot(phase: .idle, sessionID: nil, startDate: nil, message: nil)
    }
    func dismissResult() {}
    func beginShutdown() {}
    func finishShutdown() async {}
}

final class RecordingTriggerRouterTests: XCTestCase {
    @MainActor
    func testPushOwnershipAndMouseBoundary() {
        let recording = RouterRecording()
        let scheduler = ManualScheduler()
        let router = RecordingTriggerRouter(recording: recording, scheduler: scheduler)
        router.handle(.toggle)
        router.handle(.pushDown)
        router.handle(.pushUp)
        XCTAssertEqual(recording.stops, 0)
        router.handle(.toggle)
        router.handle(.pushDown)
        router.handle(.pushUp)
        XCTAssertEqual(recording.stops, 2)
        router.handle(.mouseDown)
        scheduler.advance(by: 0.29)
        router.handle(.mouseUp)
        XCTAssertEqual(recording.stops, 2)
        router.handle(.toggle)
        router.handle(.mouseDown)
        scheduler.advance(by: 0.3)
        router.handle(.mouseUp)
        XCTAssertEqual(recording.stops, 4)
    }
}
