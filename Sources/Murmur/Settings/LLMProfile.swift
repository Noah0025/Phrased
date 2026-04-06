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
