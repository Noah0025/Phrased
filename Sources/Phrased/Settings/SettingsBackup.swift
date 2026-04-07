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
                // Copy to a temp file so PhrasedSettings.load (which may write back after
                // migration) never touches the user's original backup.
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("json")
                try FileManager.default.copyItem(at: url, to: tmp)
                defer { try? FileManager.default.removeItem(at: tmp) }
                let settings = try PhrasedSettings.load(from: tmp)
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
