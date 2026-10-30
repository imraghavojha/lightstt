import Foundation
import LightTTSRuntime
import XCTest

@MainActor
final class ModelResidencyPolicyTests: XCTestCase {
    func testPolicyDecisions() {
        let ac = ModelResidencyPolicy(keepLoaded: false, onACPower: true, unloadAfter: 10)
        let battery = ModelResidencyPolicy(keepLoaded: true, onACPower: false, unloadAfter: 10)
        let noKeep = ModelResidencyPolicy(keepLoaded: false, onACPower: false, unloadAfter: 10)
        XCTAssertNil(ac.idleUnloadDelay(for: .idle))
        XCTAssertEqual(battery.idleUnloadDelay(for: .idle), 10)
        XCTAssertEqual(noKeep.idleUnloadDelay(for: .idle), 0)
        for phase: RecordingPhase in [.starting, .recording, .processing(.transcribing), .done] {
            XCTAssertNil(noKeep.idleUnloadDelay(for: phase))
        }
        XCTAssertEqual(
            ModelResidencyPolicy(keepLoaded: true, onACPower: false, unloadAfter: 0)
                .idleUnloadDelay(for: .idle), 1)
    }
}
