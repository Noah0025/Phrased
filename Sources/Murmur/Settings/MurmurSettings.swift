import Foundation
import AppKit

struct MurmurSettings: Codable, Equatable {
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
    var audioSource: String = "microphone"

    // Hotkey — UInt16.max means modifier-only double-tap (e.g. double-tap Ctrl)
    var hotkeyKeyCode: UInt16 = UInt16.max
    var hotkeyModifiers: [String] = ["control"]

    // In-app shortcuts
    var appShortcuts: [AppShortcut] = AppShortcut.defaults

    // Output
    var defaultOutputMode: String = "copy"

    // History
    var historyGroupMode: HistoryGroupMode = .date
    var historyMaxEntries: Int = 500

    // Built-in templates (editable, can be restored to defaults)
    var editedBuiltins: [PromptTemplate] = PromptTemplate.builtins

    // Custom templates
    var customTemplates: [PromptTemplate] = []

    var allTemplates: [PromptTemplate] { editedBuiltins + customTemplates }

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
        // Migrate old sentinel: keyCode 0 used to mean modifier-only; now UInt16.max
        if hotkeyKeyCode == 0 && !hotkeyModifiers.isEmpty { hotkeyKeyCode = UInt16.max }

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

        // Remove built-in LLM preset profiles that user never configured (empty model),
        // but only if at least one configured/custom profile will remain.
        let builtinLLMIDs = Set([LLMProfile.builtinOllama.id,
                                  LLMProfile.builtinLMStudio.id,
                                  LLMProfile.builtinJan.id])
        let configuredProfiles = localProfiles.filter { !builtinLLMIDs.contains($0.id) || !$0.selectedModel.isEmpty }
        if !configuredProfiles.isEmpty {
            localProfiles = configuredProfiles
        }
        // If localProfiles is still empty (e.g. corrupted settings), restore the default
        if localProfiles.isEmpty {
            localProfiles = [LLMProfile.builtinOllama]
        }
        if !localProfiles.contains(where: { $0.id == selectedProfileID }) {
            selectedProfileID = localProfiles.first?.id ?? UUID()
        }

        // Sync app shortcuts with current defaults:
        // - remove retired IDs (e.g. "copy")
        // - add new IDs
        // - update display names (preserving user's keyCode/modifiers)
        // - reorder to match defaults order
        let validIDs = Set(AppShortcut.defaults.map { $0.id })
        appShortcuts.removeAll { !validIDs.contains($0.id) }
        let existingIDs = Set(appShortcuts.map { $0.id })
        for def in AppShortcut.defaults where !existingIDs.contains(def.id) {
            appShortcuts.append(def)
        }
        for def in AppShortcut.defaults {
            if let idx = appShortcuts.firstIndex(where: { $0.id == def.id }) {
                appShortcuts[idx].name = def.name
            }
        }
        appShortcuts.sort { a, b in
            let ai = AppShortcut.defaults.firstIndex { $0.id == a.id } ?? Int.max
            let bi = AppShortcut.defaults.firstIndex { $0.id == b.id } ?? Int.max
            return ai < bi
        }

        // Sync editedBuiltins with current builtins: remove retired, add new
        let currentBuiltinIDs = Set(PromptTemplate.builtins.map { $0.id })
        editedBuiltins.removeAll { !currentBuiltinIDs.contains($0.id) }
        let existingBuiltinIDs = Set(editedBuiltins.map { $0.id })
        for def in PromptTemplate.builtins where !existingBuiltinIDs.contains(def.id) {
            editedBuiltins.append(def)
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
        // Patch any missing non-optional fields added in newer versions so that
        // old settings files don't cause a full decode failure (keyNotFound).
        let patchedData = try patchMissingFields(in: data)
        var s = try JSONDecoder().decode(MurmurSettings.self, from: patchedData)
        let needsSave = s.hasLegacyFields
        s.migrate()
        if needsSave { try? s.save(to: url) }
        return s
    }

    /// Fill in any keys missing from an old settings JSON using the current defaults.
    /// This prevents a `keyNotFound` decode failure when new non-optional fields are added.
    private static func patchMissingFields(in data: Data) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        let defaultData = try JSONEncoder().encode(MurmurSettings())
        guard let defaults = try JSONSerialization.jsonObject(with: defaultData) as? [String: Any] else {
            return data
        }
        let merged = recursiveMerge(defaults: defaults, into: json)
        guard let patched = merged as? [String: Any] else { return data }
        if NSDictionary(dictionary: patched).isEqual(to: json) { return data }
        json = patched
        return try JSONSerialization.data(withJSONObject: json)
    }

    private static func recursiveMerge(defaults: Any, into current: Any) -> Any {
        guard let d = defaults as? [String: Any], var c = current as? [String: Any] else {
            return current
        }
        for (key, defaultValue) in d {
            if let currentValue = c[key] {
                c[key] = recursiveMerge(defaults: defaultValue, into: currentValue)
            } else {
                c[key] = defaultValue
            }
        }
        return c
    }

    private var hasLegacyFields: Bool {
        localBaseURL != nil || localAPIKey != nil || localModel != nil ||
        ollamaModel != nil || openAIBaseURL != nil || openAIAPIKey != nil || openAIModel != nil ||
        llmProviderID == "ollama" || llmProviderID == "openai" ||
        (llmProviderID == "cloud" && !cloudBaseURL.isEmpty) ||
        asrProviderID != nil ||
        asrProfiles.contains(where: { $0.providerType == "whisper" }) ||
        asrProfiles.contains(where: { $0.isBuiltIn && $0.id != ASRProfile.builtinSFSpeech.id }) ||
        AppShortcut.defaults.contains(where: { def in !appShortcuts.contains(where: { $0.id == def.id }) }) ||
        appShortcuts.contains(where: { s in !AppShortcut.defaults.contains(where: { $0.id == s.id }) }) ||
        appShortcuts.contains(where: { s in AppShortcut.defaults.first(where: { $0.id == s.id })?.name != s.name }) ||
        (hotkeyKeyCode == 0 && !hotkeyModifiers.isEmpty)
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
