import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set { if let v = newValue, indices.contains(index) { self[index] = v } }
    }
}

struct LLMProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var apiKey: String = ""
    var selectedModel: String = ""
    var isBuiltIn: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, baseURL, apiKey, selectedModel, isBuiltIn
    }

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        apiKey: String = "",
        selectedModel: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.selectedModel = selectedModel
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? ""
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
    }

    var keychainKey: String { "llm-\(id.uuidString)" }

    func saveKeyToKeychain() {
        guard !apiKey.isEmpty else { return }
        KeychainHelper.save(key: keychainKey, data: apiKey)
    }

    mutating func loadKeyFromKeychain() {
        apiKey = KeychainHelper.load(key: keychainKey) ?? ""
    }

    // MARK: - Built-in presets

    static let builtinOllama   = LLMProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                                    name: "Ollama",
                                                    baseURL: "http://localhost:11434",
                                                    isBuiltIn: true)
    static let builtinLMStudio = LLMProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                                                    name: "LM Studio",
                                                    baseURL: "http://localhost:1234",
                                                    isBuiltIn: true)
    static let builtinJan      = LLMProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                                                    name: "Jan",
                                                    baseURL: "http://localhost:1337",
                                                    isBuiltIn: true)

    static var defaultProfiles: [LLMProfile] { [] }

    // MARK: - Install URLs (for "install" button when models not found)

    var installURL: String? {
        switch baseURL {
        case "http://localhost:11434": return "https://ollama.com"
        case "http://localhost:1234":  return "https://lmstudio.ai"
        case "http://localhost:1337":  return "https://jan.ai"
        default: return nil
        }
    }
}
