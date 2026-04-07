import AppKit
import UniformTypeIdentifiers

enum SettingsBackup {
    /// 弹出 NSSavePanel，将 PhrasedSettings 导出为 JSON 文件
    static func exportSettings(_ settings: PhrasedSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "phrased-settings.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            // API keys are stored in Keychain and intentionally omitted from Codable output.
            guard let data = try? encoder.encode(settings) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 弹出 NSOpenPanel，读取 JSON 并解码，成功则调用 completion(settings)，失败弹 NSAlert
    static func importSettings(completion: @escaping (PhrasedSettings?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            do {
                let data = try Data(contentsOf: url)
                let settings = try JSONDecoder().decode(PhrasedSettings.self, from: data)
                completion(settings)
            } catch {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("settings.backup.import_failed", comment: "")
                alert.informativeText = error.localizedDescription
                alert.runModal()
                completion(nil)
            }
        }
    }
}
