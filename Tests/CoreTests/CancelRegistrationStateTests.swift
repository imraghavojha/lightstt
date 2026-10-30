import XCTest
@testable import LightTTSCore

final class CancelRegistrationStateTests: XCTestCase {
    func testProcessingAndLoadingRemainCancelable() {
        for session in ["starting", "recording", "processing", "loading"] {
            XCTAssertTrue(CancelRegistrationState.isActiveSession(session))
        }
        for session in ["idle", "done", "error"] {
            XCTAssertFalse(CancelRegistrationState.isActiveSession(session))
        }
    }

    func testRegistrationFollowsRecordingAndMonitorLifecycle() {
        var state = CancelRegistrationState()
        XCTAssertFalse(state.shouldRegister)
        state.setInstalled(true)
        XCTAssertFalse(state.shouldRegister)
        state.setRecording(true)
        XCTAssertTrue(state.shouldRegister)
        state.setRecording(true)
        XCTAssertTrue(state.shouldRegister)
        state.setInstalled(false)
        XCTAssertFalse(state.shouldRegister)
        state.setInstalled(true)
        XCTAssertTrue(state.shouldRegister)
        state.setRecording(false)
        XCTAssertFalse(state.shouldRegister)
    }
}
