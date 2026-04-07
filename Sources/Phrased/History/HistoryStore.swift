import Foundation

// MARK: - HistoryGroupMode

enum HistoryGroupMode: String, CaseIterable, Identifiable, Codable {
    case date     = "date"
    case template = "template"
    case app      = "app"
    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .date:
            return NSLocalizedString("history.group.date", comment: "")
        case .template:
            return NSLocalizedString("history.group.template", comment: "")
        case .app:
            return NSLocalizedString("history.group.app", comment: "")
        }
    }
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
    private let queue = DispatchQueue(label: "phrased.history.io")
    private var cache: [HistoryEntry]?
    /// Days to retain history entries. 0 = keep forever.
    private var _retentionDays: Int = 90
    var retentionDays: Int {
        get { queue.sync { _retentionDays } }
        set { queue.sync { _retentionDays = newValue } }
    }

    init(storageURL: URL = HistoryStore.defaultStorageURL()) {
        self.storageURL = storageURL
    }

    static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Phrased", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    private func loadUnlocked() throws -> [HistoryEntry] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: storageURL)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([HistoryEntry].self, from: data)
            cache = entries
            return entries
        } catch is DecodingError {
            let backupURL = storageURL.deletingLastPathComponent()
                .appendingPathComponent("history.corrupted.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: storageURL, to: backupURL)
            try? FileManager.default.removeItem(at: storageURL)
            cache = []
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyStoreCorruptionRecovered, object: nil)
            }
            return []
        }
    }

    func load() throws -> [HistoryEntry] {
        try queue.sync { try loadUnlocked() }
    }

    func append(_ entry: HistoryEntry) throws {
        try queue.sync {
            var entries = try loadUnlocked()
            entries.append(entry)
            if _retentionDays > 0 {
                let cutoff = Date().addingTimeInterval(-Double(_retentionDays) * 86400)
                entries.removeAll { $0.createdAt < cutoff }
            }
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

    /// Prune entries older than the current retention period and persist the result.
    func pruneIfNeeded() throws {
        try queue.sync {
            guard _retentionDays > 0 else { return }
            var entries = try loadUnlocked()
            let cutoff = Date().addingTimeInterval(-Double(_retentionDays) * 86400)
            let before = entries.count
            entries.removeAll { $0.createdAt < cutoff }
            guard entries.count < before else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: storageURL)
            } else {
                try encoder.encode(entries).write(to: storageURL, options: .atomic)
            }
            cache = entries
        }
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
    static let historyStoreDidChange = Notification.Name("phrased.historyStore.didChange")
    static let historyStoreCorruptionRecovered = Notification.Name("phrased.historyStore.corruptionRecovered")
}
