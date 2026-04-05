import Foundation

struct ASRProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    /// "sfspeech" | "api"
    var providerType: String
    var baseURL: String = ""
    var apiKey: String = ""
    var model: String = ""
    var isBuiltIn: Bool = false

    // MARK: - Built-in presets

    static let builtinSFSpeech = ASRProfile(
        id: UUID(uuidString: "00000000-0000-0000-0001-000000000001")!,
        name: "macOS 语音识别",
        providerType: "sfspeech",
        isBuiltIn: true
    )

    static var defaultProfiles: [ASRProfile] { [builtinSFSpeech] }
}
