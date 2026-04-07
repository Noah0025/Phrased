import Foundation

struct VocabEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var trigger: String
    var expansion: String
}

class VocabularyStore {
    private(set) var words: [VocabEntry]

    init(words: [VocabEntry] = []) { self.words = words }

    func apply(to text: String) -> String {
        var result = text
        for entry in words where !entry.trigger.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: entry.trigger)
            guard let regex = try? NSRegularExpression(
                pattern: "(?<![\\w])\(escaped)(?![\\w])"
            ) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let template = NSRegularExpression.escapedTemplate(for: entry.expansion)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Phrased", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vocabulary.json")
    }

    func save(to url: URL = VocabularyStore.defaultStorageURL()) throws {
        try JSONEncoder().encode(words).write(to: url, options: .atomic)
    }

    static func load(from url: URL = VocabularyStore.defaultStorageURL()) throws -> VocabularyStore {
        let words = try JSONDecoder().decode([VocabEntry].self, from: Data(contentsOf: url))
        return VocabularyStore(words: words)
    }

    static func loadOrDefault() -> VocabularyStore { (try? load()) ?? VocabularyStore() }
}
