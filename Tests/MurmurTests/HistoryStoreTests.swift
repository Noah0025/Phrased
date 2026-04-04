import XCTest
@testable import Murmur

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

    func test_cappedAt500() throws {
        for i in 0..<505 {
            try store.append(HistoryEntry(id: UUID(), createdAt: Date(), input: "\(i)", output: "",
                                          templateName: "", appName: nil))
        }
        XCTAssertEqual(try store.load().count, 500)
    }
}
