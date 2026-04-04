import Foundation
import AppKit

struct MurmurSettings: Codable {
    // LLM
    var llmProviderID: String = "ollama"        // "ollama" | "openai"
    var ollamaModel: String = "qwen2.5:7b"
    var openAIBaseURL: String = "https://api.openai.com"
    var openAIAPIKey: String = ""
    var openAIModel: String = "gpt-4o-mini"

    // ASR
    var asrProviderID: String = "whisper"       // "whisper" only for now

    // Audio source
    var audioSource: String = "systemAudio"     // "systemAudio" | "microphone"

    // Hotkey (default ⌥Space: keyCode=49, modifiers=["option"])
    var hotkeyKeyCode: UInt16 = 49
    var hotkeyModifiers: [String] = ["option"]  // "option"|"command"|"control"|"shift"

    // Output
    var defaultOutputMode: String = "copy"      // "copy" | "inject"

    // Custom templates (builtins are always prepended at runtime)
    var customTemplates: [PromptTemplate] = []

    var allTemplates: [PromptTemplate] { PromptTemplate.builtins + customTemplates }

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
        return try JSONDecoder().decode(MurmurSettings.self, from: data)
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
