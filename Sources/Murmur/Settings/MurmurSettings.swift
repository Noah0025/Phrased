import Foundation
import AppKit

struct MurmurSettings: Codable {
    // LLM provider: "local" | "cloud"
    var llmProviderID: String = "local"

    // Local model profiles
    var localProfiles: [LLMProfile] = LLMProfile.defaultProfiles
    var selectedProfileID: UUID = LLMProfile.builtinOllama.id

    // Cloud API (OpenAI-compatible)
    var cloudBaseURL: String = ""
    var cloudAPIKey: String = ""
    var cloudModel: String = ""

    // Legacy keys — kept for migration only
    var localBaseURL: String? = nil
    var localAPIKey: String? = nil
    var localModel: String? = nil
    var ollamaModel: String? = nil
    var openAIBaseURL: String? = nil
    var openAIAPIKey: String? = nil
    var openAIModel: String? = nil

    // ASR profiles
    var asrProfiles: [ASRProfile] = ASRProfile.defaultProfiles
    var selectedASRProfileID: UUID = ASRProfile.builtinSFSpeech.id

    // Legacy ASR key — kept for migration only
    var asrProviderID: String? = nil

    // Audio source
    var audioSource: String = "systemAudio"

    // Hotkey
    var hotkeyKeyCode: UInt16 = 49
    var hotkeyModifiers: [String] = ["option"]

    // Output
    var defaultOutputMode: String = "copy"

    // History
    var historyGroupMode: HistoryGroupMode = .date
    var historyMaxEntries: Int = 500

    // Custom templates
    var customTemplates: [PromptTemplate] = []

    var allTemplates: [PromptTemplate] { PromptTemplate.builtins + customTemplates }

    // MARK: - Helpers

    var selectedProfile: LLMProfile {
        localProfiles.first { $0.id == selectedProfileID }
            ?? localProfiles.first
            ?? LLMProfile.builtinOllama
    }

    var selectedASRProfile: ASRProfile {
        asrProfiles.first { $0.id == selectedASRProfileID }
            ?? asrProfiles.first
            ?? ASRProfile.builtinSFSpeech
    }

    // MARK: - Migration

    mutating func migrate() {
        // Provider ID
        if llmProviderID == "ollama" { llmProviderID = "local" }
        if llmProviderID == "openai" { llmProviderID = "cloud" }

        // Migrate old localBaseURL into the Ollama built-in profile's selectedModel
        if let model = localModel ?? ollamaModel, !model.isEmpty {
            if let idx = localProfiles.firstIndex(where: { $0.id == LLMProfile.builtinOllama.id }) {
                if localProfiles[idx].selectedModel.isEmpty {
                    localProfiles[idx].selectedModel = model
                }
            }
        }
        if let key = localAPIKey, !key.isEmpty {
            if let idx = localProfiles.firstIndex(where: { $0.id == LLMProfile.builtinOllama.id }) {
                if localProfiles[idx].apiKey.isEmpty {
                    localProfiles[idx].apiKey = key
                }
            }
        }
        if let url = openAIBaseURL { cloudBaseURL = url }
        if let key = openAIAPIKey, !key.isEmpty { cloudAPIKey = key }
        if let model = openAIModel, !model.isEmpty { cloudModel = model }

        // Migrate legacy asrProviderID
        if let _ = asrProviderID {
            selectedASRProfileID = ASRProfile.builtinSFSpeech.id
            asrProviderID = nil
        }

        // Migrate old "whisper" providerType profiles to "api" pointing to localhost
        for idx in asrProfiles.indices where asrProfiles[idx].providerType == "whisper" {
            asrProfiles[idx].providerType = "api"
            if asrProfiles[idx].baseURL.isEmpty {
                asrProfiles[idx].baseURL = "http://localhost:8000"
            }
            if asrProfiles[idx].model.isEmpty {
                asrProfiles[idx].model = "whisper-1"
            }
            asrProfiles[idx].isBuiltIn = false
        }

        // Remove any stale builtin UUIDs that no longer exist
        let validBuiltinIDs = Set([ASRProfile.builtinSFSpeech.id])
        asrProfiles.removeAll { $0.isBuiltIn && !validBuiltinIDs.contains($0.id) }
        if !asrProfiles.contains(where: { $0.id == ASRProfile.builtinSFSpeech.id }) {
            asrProfiles.insert(ASRProfile.builtinSFSpeech, at: 0)
        }
        if !validBuiltinIDs.contains(selectedASRProfileID) &&
           !asrProfiles.contains(where: { $0.id == selectedASRProfileID }) {
            selectedASRProfileID = ASRProfile.builtinSFSpeech.id
        }

        // Migrate cloud LLM config into localProfiles (unified profile list)
        if llmProviderID == "cloud", !cloudBaseURL.isEmpty {
            if !localProfiles.contains(where: { $0.baseURL == cloudBaseURL }) {
                let cloudProfile = LLMProfile(
                    name: cloudModel.isEmpty ? "云端 API" : cloudModel,
                    baseURL: cloudBaseURL,
                    apiKey: cloudAPIKey,
                    selectedModel: cloudModel
                )
                localProfiles.append(cloudProfile)
                selectedProfileID = cloudProfile.id
            }
            cloudBaseURL = ""; cloudAPIKey = ""; cloudModel = ""
            llmProviderID = "local"
        }

        // Remove built-in LLM preset profiles that user never configured (empty model)
        let builtinLLMIDs = Set([LLMProfile.builtinOllama.id,
                                  LLMProfile.builtinLMStudio.id,
                                  LLMProfile.builtinJan.id])
        localProfiles.removeAll { builtinLLMIDs.contains($0.id) && $0.selectedModel.isEmpty }
        if !localProfiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = localProfiles.first?.id ?? UUID()
        }

        // Clear legacy fields so they don't re-trigger migration on next load
        localBaseURL = nil; localAPIKey = nil; localModel = nil
        ollamaModel = nil; openAIBaseURL = nil; openAIAPIKey = nil; openAIModel = nil
    }

    // MARK: - Restore defaults

    mutating func restoreDefaultProfiles() {
        for preset in LLMProfile.defaultProfiles {
            if let idx = localProfiles.firstIndex(where: { $0.id == preset.id }) {
                // Reset name and URL but keep selectedModel
                localProfiles[idx].name = preset.name
                localProfiles[idx].baseURL = preset.baseURL
            } else {
                localProfiles.append(preset)
            }
        }
    }

    // MARK: - Persistence

    static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    func save(to url: URL = MurmurSettings.defaultStorageURL()) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = MurmurSettings.defaultStorageURL()) throws -> MurmurSettings {
        let data = try Data(contentsOf: url)
        var s = try JSONDecoder().decode(MurmurSettings.self, from: data)
        let needsSave = s.hasLegacyFields
        s.migrate()
        if needsSave { try? s.save(to: url) }
        return s
    }

    private var hasLegacyFields: Bool {
        localBaseURL != nil || localAPIKey != nil || localModel != nil ||
        ollamaModel != nil || openAIBaseURL != nil || openAIAPIKey != nil || openAIModel != nil ||
        llmProviderID == "ollama" || llmProviderID == "openai" ||
        (llmProviderID == "cloud" && !cloudBaseURL.isEmpty) ||
        asrProviderID != nil ||
        asrProfiles.contains(where: { $0.providerType == "whisper" }) ||
        asrProfiles.contains(where: { $0.isBuiltIn && $0.id != ASRProfile.builtinSFSpeech.id })
    }

    static func loadOrDefault() -> MurmurSettings {
        (try? load()) ?? MurmurSettings()
    }

    var hotkeyNSModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if hotkeyModifiers.contains("option")  { flags.insert(.option) }
        if hotkeyModifiers.contains("command") { flags.insert(.command) }
        if hotkeyModifiers.contains("control") { flags.insert(.control) }
        if hotkeyModifiers.contains("shift")   { flags.insert(.shift) }
        return flags
    }
}
