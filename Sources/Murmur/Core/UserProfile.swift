import Foundation

struct UserProfile: Codable {
    var version: Int = 1
    var updatedAt: String = ""
    var preferredOutputLanguage: String = "en"
    var preferredInputLanguage: String = "zh"
    var tone: String = ""
    var formality: String = ""
    var patterns: [String] = []
    var historySummary: String? = nil
    var contexts: [String] = []

    /// True when no meaningful personal data has been accumulated yet.
    var isEmpty: Bool {
        historySummary == nil && patterns.isEmpty && contexts.isEmpty
    }

    static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_profile.json")
    }

    func save(to url: URL = UserProfile.defaultStorageURL()) throws {
        var copy = self
        copy.updatedAt = ISO8601DateFormatter().string(from: Date())
        let data = try JSONEncoder().encode(copy)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = UserProfile.defaultStorageURL()) throws -> UserProfile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    static func loadOrDefault() -> UserProfile {
        (try? load()) ?? UserProfile()
    }
}
