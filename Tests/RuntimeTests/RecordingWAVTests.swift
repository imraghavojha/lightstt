import XCTest
@testable import LightTTSRuntime

final class RecordingWAVTests: XCTestCase {
    func testFloatWAVHeaderAndBitPatterns() {
        let data = RecordingWAV.encode([0, -1, 0.5, Float(bitPattern: 0x7fc01234)])
        XCTAssertEqual(data.count, 60)
        XCTAssertEqual(
            Array(data.prefix(12)), Array("RIFF".utf8) + [52, 0, 0, 0] + Array("WAVE".utf8))
        XCTAssertEqual(Array(data[20..<24]), [3, 0, 1, 0])
        XCTAssertEqual(Array(data[24..<28]), [0x80, 0x3e, 0, 0])
        XCTAssertEqual(Array(data[40..<44]), [16, 0, 0, 0])
        XCTAssertEqual(
            Array(data[44...]),
            [0, 0, 0, 0, 0, 0, 0x80, 0xbf, 0, 0, 0, 0x3f, 0x34, 0x12, 0xc0, 0x7f])
        XCTAssertEqual(RecordingWAV.encode([]).count, 44)
    }
}
