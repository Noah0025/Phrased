import Foundation

enum ASRProviderType: String, Codable {
    case sfspeech
    case api
}

struct ASRProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var providerType: ASRProviderType
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var isBuiltIn: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id, name, providerType, baseURL, apiKey, model, isBuiltIn
    }

    init(
        id: UUID = UUID(),
        name: String,
        providerType: ASRProviderType,
        baseURL: String = "",
        apiKey: String = "",
        model: String = "",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.isBuiltIn = isBuiltIn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)

        let rawProviderType = try container.decode(String.self, forKey: .providerType)
        if rawProviderType == "whisper" {
            providerType = .api
            baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
            apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
            model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
            isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
            if baseURL.isEmpty { baseURL = "http://localhost:8000" }
            if model.isEmpty { model = "whisper-1" }
            isBuiltIn = false
            return
        }

        guard let providerType = ASRProviderType(rawValue: rawProviderType) else {
            throw DecodingError.dataCorruptedError(
                forKey: .providerType,
                in: container,
                debugDescription: "Invalid providerType: \(rawProviderType)"
            )
        }

        self.providerType = providerType
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(providerType.rawValue, forKey: .providerType)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(isBuiltIn, forKey: .isBuiltIn)
    }

    var keychainKey: String { "asr-\(id.uuidString)" }

    func saveKeyToKeychain() {
        if apiKey.isEmpty {
            KeychainHelper.delete(key: keychainKey)
        } else {
            KeychainHelper.save(key: keychainKey, data: apiKey)
        }
    }

    mutating func loadKeyFromKeychain() {
        apiKey = KeychainHelper.load(key: keychainKey) ?? ""
    }

    // MARK: - Built-in presets

    static let builtinSFSpeech = ASRProfile(
        id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
        name: NSLocalizedString("audio.profile.macos_speech", comment: ""),
        providerType: .sfspeech,
        isBuiltIn: true
    )

    static var defaultProfiles: [ASRProfile] { [builtinSFSpeech] }

    // MARK: - Cloud presets

    struct CloudPreset {
        let name: String
        let baseURL: String
        let model: String
    }

    static let cloudPresets: [CloudPreset] = [
        CloudPreset(name: "OpenAI Whisper",  baseURL: "https://api.openai.com",                          model: "whisper-1"),
        CloudPreset(name: "Groq Whisper",    baseURL: "https://api.groq.com/openai",                     model: "whisper-large-v3"),
        CloudPreset(name: "阿里云百炼",       baseURL: "https://dashscope.aliyuncs.com/compatible-mode",  model: "paraformer-realtime-v2"),
    ]
}
