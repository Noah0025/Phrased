import SwiftUI

extension SettingsView {
    var generalPane: some View {
        Form {
            Section("settings.general.behavior") {
                Toggle("settings.general.launch_at_login", isOn: $draft.launchAtLogin)
                    .onChange(of: draft.launchAtLogin) { enabled in
                        LaunchAtLoginHelper.set(enabled: enabled)
                    }
                Toggle("settings.general.play_completion_sound", isOn: $draft.playCompletionSound)
            }

            Section {
                Picker("settings.general.language", selection: $draft.appLanguage) {
                    Text("settings.general.language.chinese").tag(AppLanguage.zhHans)
                    Text("settings.general.language.english").tag(AppLanguage.english)
                }
                .onChange(of: draft.appLanguage) { lang in
                    switch lang {
                    case .system:   UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    case .zhHans:   UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
                    case .english:  UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
                    }
                }
            } header: {
                Text("settings.general.language")
            } footer: {
                HStack(alignment: .firstTextBaseline) {
                    Text("settings.general.language.restart_note")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("settings.general.language.restart_button") {
                        let url = Bundle.main.bundleURL
                        let task = Process()
                        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                        task.arguments = [url.path]
                        try? task.run()
                        NSApplication.shared.terminate(nil)
                    }
                }
                .font(.caption)
            }

            Section {
                HStack {
                    Button("settings.backup.export") { SettingsBackup.exportSettings(draft) }
                    Spacer()
                    Button("settings.backup.import") {
                        SettingsBackup.importSettings { imported in
                            guard let imported else { return }
                            draft = imported
                            onSave(imported)
                        }
                    }
                }
            } header: {
                Text("settings.backup.settings_file")
            } footer: {
                Text("settings.backup.note")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
