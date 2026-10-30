import Foundation
import XCTest
@testable import LightTTSCore

final class HistoryPersistenceTests: XCTestCase {
    func testFailedAudioAndJSONAreRetried() {
        let folder = URL(fileURLWithPath: "/history")
        var fail = true
        var written: [String: Data] = [:]
        let persistence = HistoryPersistence { data, url in
            if fail { throw CocoaError(.fileWriteUnknown) }
            written[url.lastPathComponent] = data
        }
        persistence.enqueueRecording(Data([1]), named: "one.wav")
        XCTAssertNotNil(persistence.save(Data([2]), in: folder, fallback: nil).error)
        fail = false
        XCTAssertNil(persistence.save(Data([3]), in: folder, fallback: nil).error)
        XCTAssertEqual(written["one.wav"], Data([1]))
        XCTAssertEqual(written["history.json"], Data([3]))
    }

    func testJSONFailureRetainsAudioForRetry() {
        let folder = URL(fileURLWithPath: "/history")
        var failJSON = true
        var audioWrites = 0
        let persistence = HistoryPersistence { _, url in
            if url.lastPathComponent == "history.json" && failJSON {
                throw CocoaError(.fileWriteUnknown)
            }
            if url.pathExtension == "wav" { audioWrites += 1 }
        }
        persistence.enqueueRecording(Data([1]), named: "one.wav")
        XCTAssertNotNil(persistence.save(Data([2]), in: folder, fallback: nil).error)
        failJSON = false
        XCTAssertNil(persistence.save(Data([2]), in: folder, fallback: nil).error)
        XCTAssertEqual(audioWrites, 2)
    }

    func testWriterFailureFallsBackWithPendingAudio() {
        let configured = FileManager.default.temporaryDirectory
        let fallback = configured.appendingPathComponent(UUID().uuidString)
        var writes: [URL: Data] = [:]
        let persistence = HistoryPersistence { data, url in
            if url.path.hasPrefix(configured.path + "/Recordings") {
                throw CocoaError(.fileWriteNoPermission)
            }
            writes[url] = data
        }
        persistence.enqueueRecording(Data([7]), named: "one.wav")
        let result = persistence.save(Data([8]), in: configured, fallback: fallback)
        XCTAssertTrue(result.fellBack)
        XCTAssertNil(result.error)
        XCTAssertEqual(writes[fallback.appendingPathComponent("Recordings/one.wav")], Data([7]))
        XCTAssertEqual(writes[fallback.appendingPathComponent("history.json")], Data([8]))
    }

    func testUnavailableConfiguredFolderFallsBack() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configured = root.appendingPathComponent("missing")
        let fallback = root.appendingPathComponent("default")
        let persistence = HistoryPersistence()
        persistence.enqueueRecording(Data([4]), named: "one.wav")
        let result = persistence.save(Data([5]), in: configured, fallback: fallback)
        XCTAssertTrue(result.fellBack)
        XCTAssertNil(result.error)
        XCTAssertEqual(
            try Data(contentsOf: fallback.appendingPathComponent("Recordings/one.wav")), Data([4]))
        XCTAssertEqual(
            try Data(contentsOf: fallback.appendingPathComponent("history.json")), Data([5]))
    }
}
