import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID
    var createdAt: Date
    var input: String
    var output: String
    var templateName: String
    var appName: String?
}

class HistoryStore {
    private let storageURL: URL

    init(storageURL: URL = HistoryStore.defaultStorageURL()) {
        self.storageURL = storageURL
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func load() throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([HistoryEntry].self, from: Data(contentsOf: storageURL))
    }

    func append(_ entry: HistoryEntry) throws {
        var entries = (try? load()) ?? []
        entries.append(entry)
        if entries.count > 500 { entries = Array(entries.suffix(500)) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(entries).write(to: storageURL, options: .atomic)
    }

    func clear() throws {
        try FileManager.default.removeItem(at: storageURL)
    }
}
