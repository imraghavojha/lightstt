import XCTest
@testable import LightTTSCore

final class ModelCatalogTests: XCTestCase {
    func testDefaultModelIsAvailableInCatalog() throws {
        let model = try XCTUnwrap(
            ModelCatalog.load().first { $0.id == ModelDefaults.selectedModel }
        )
        XCTAssertEqual(model.engine, "parakeet")
    }

    func testCatalogHasUniqueSafeIDs() throws {
        let models = try ModelCatalog.load()
        XCTAssertFalse(models.isEmpty)
        XCTAssertEqual(Set(models.map(\.id)).count, models.count)
        for model in models {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertFalse(model.id.contains("/"))
            XCTAssertNotEqual(model.id, ".")
            XCTAssertNotEqual(model.id, "..")
        }
    }
}
