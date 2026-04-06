import Foundation

// MARK: - HistoryGroupMode

enum HistoryGroupMode: String, CaseIterable, Identifiable, Codable {
    case date     = "按日期"
    case template = "按风格"
    case app      = "按来源"
    var id: String { rawValue }
}

// MARK: - HistoryEntry

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
    private let queue = DispatchQueue(label: "murmur.history.io")
    private var cache: [HistoryEntry]?
    var maxEntries: Int = 500

    init(storageURL: URL = HistoryStore.defaultStorageURL()) {
        self.storageURL = storageURL
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadUnlocked() throws -> [HistoryEntry] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([HistoryEntry].self, from: Data(contentsOf: storageURL))
        cache = entries
        return entries
    }

    func load() throws -> [HistoryEntry] {
        try queue.sync { try loadUnlocked() }
    }

    func append(_ entry: HistoryEntry) throws {
        try queue.sync {
            var entries = try loadUnlocked()
            entries.append(entry)
            if entries.count > maxEntries { entries = Array(entries.suffix(maxEntries)) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(entries).write(to: storageURL, options: .atomic)
            cache = entries
        }
        NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
    }

    func delete(ids: Set<UUID>) throws {
        try queue.sync {
            var entries = try loadUnlocked()
            entries.removeAll { ids.contains($0.id) }
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: storageURL)
            } else {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                try encoder.encode(entries).write(to: storageURL, options: .atomic)
            }
            cache = entries
        }
        NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
    }

    func clear() throws {
        try queue.sync {
            if FileManager.default.fileExists(atPath: storageURL.path) {
                try FileManager.default.removeItem(at: storageURL)
            }
            cache = []
        }
        NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
    }
}

extension Notification.Name {
    static let historyStoreDidChange = Notification.Name("murmur.historyStore.didChange")
}
