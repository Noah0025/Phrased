import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

// MARK: - Permission status

private enum PermStatus {
    case granted, denied
    var isGranted: Bool { self == .granted }
}

private func checkAccessibility()   -> PermStatus { AXIsProcessTrusted() ? .granted : .denied }
private func checkMicrophone()      -> PermStatus { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized ? .granted : .denied }
private func checkScreenRecording() -> PermStatus { CGPreflightScreenCaptureAccess() ? .granted : .denied }
private func checkSpeech()          -> PermStatus { SFSpeechRecognizer.authorizationStatus() == .authorized ? .granted : .denied }

// MARK: - Permission row

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let status: PermStatus
    let url: String

    var body: some View {
        Button {
            if !status.isGranted, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(status.isGranted ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 8, height: 8)
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    if !status.isGranted {
                        Text("settings.permissions.grant")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - General pane (standalone View for @State support)

extension SettingsView {
    var generalPane: some View {
        GeneralSettingsPane(draft: $draft, onSave: onSave)
    }
}

struct GeneralSettingsPane: View {
    @Binding var draft: PhrasedSettings
    let onSave: (PhrasedSettings) -> Void

    @State private var permAccessibility   = checkAccessibility()
    @State private var permMicrophone      = checkMicrophone()
    @State private var permScreenRecording = checkScreenRecording()
    @State private var permSpeech          = checkSpeech()

    var body: some View {
        Form {
            // MARK: Behavior
            Section {
                Toggle("settings.general.launch_at_login", isOn: $draft.launchAtLogin)
                    .onChange(of: draft.launchAtLogin) { enabled in
                        LaunchAtLoginHelper.set(enabled: enabled)
                    }
                Toggle("settings.general.show_in_menu_bar", isOn: $draft.showInMenuBar)
                Toggle("settings.general.play_completion_sound", isOn: $draft.playCompletionSound)
            }

            // MARK: Language
            Section {
                Picker("settings.general.language", selection: $draft.appLanguage) {
                    Text("settings.general.language.system").tag(AppLanguage.system)
                    Text("settings.general.language.chinese").tag(AppLanguage.zhHans)
                    Text("settings.general.language.english").tag(AppLanguage.english)
                }
                .onChange(of: draft.appLanguage) { lang in
                    switch lang {
                    case .system:  UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    case .zhHans:  UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
                    case .english: UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
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

            // MARK: Permissions
            Section {
                PermissionRow(
                    title: "settings.permissions.accessibility",
                    description: "settings.permissions.accessibility.description",
                    status: permAccessibility,
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PermissionRow(
                    title: "settings.permissions.microphone",
                    description: "settings.permissions.microphone.description",
                    status: permMicrophone,
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                PermissionRow(
                    title: "settings.permissions.screen_recording",
                    description: "settings.permissions.screen_recording.description",
                    status: permScreenRecording,
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
                PermissionRow(
                    title: "settings.permissions.speech_recognition",
                    description: "settings.permissions.speech_recognition.description",
                    status: permSpeech,
                    url: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"
                )
            } header: {
                Text("settings.permissions.title")
            }

            // MARK: Backup
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
        .onAppear { refreshPermissions() }
    }

    private func refreshPermissions() {
        permAccessibility   = checkAccessibility()
        permMicrophone      = checkMicrophone()
        permScreenRecording = checkScreenRecording()
        permSpeech          = checkSpeech()
    }
}
