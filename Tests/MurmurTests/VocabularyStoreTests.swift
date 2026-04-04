import XCTest
@testable import Murmur

final class VocabularyStoreTests: XCTestCase {
    func test_replacesWholeWord() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "tmr", expansion: "tomorrow")])
        XCTAssertEqual(store.apply(to: "tmr I'll be there"), "tomorrow I'll be there")
    }

    func test_noSubstringReplacement() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "imo", expansion: "in my opinion")])
        XCTAssertEqual(store.apply(to: "import this"), "import this")
    }

    func test_noMatch_returnsOriginal() {
        let store = VocabularyStore(words: [VocabEntry(trigger: "abc", expansion: "xyz")])
        XCTAssertEqual(store.apply(to: "no match"), "no match")
    }

    func test_roundTripPersistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vocab_\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = VocabularyStore(words: [VocabEntry(trigger: "g2g", expansion: "got to go")])
        try store.save(to: url)
        let loaded = try VocabularyStore.load(from: url)
        XCTAssertEqual(loaded.words.first?.trigger, "g2g")
    }
}
