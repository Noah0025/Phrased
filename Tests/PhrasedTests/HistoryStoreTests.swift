import XCTest
@testable import Phrased

final class HistoryStoreTests: XCTestCase {
    var store: HistoryStore!
    var tmpURL: URL!

    override func setUp() {
        tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        store = HistoryStore(storageURL: tmpURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpURL)
    }

    func test_appendAndLoad() throws {
        let e = HistoryEntry(id: UUID(), createdAt: Date(), input: "hi", output: "Hello!",
                             templateName: "通用", appName: nil)
        try store.append(e)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].input, "hi")
    }

    func test_emptyOnMissingFile() throws {
        XCTAssertTrue(try store.load().isEmpty)
    }

}
