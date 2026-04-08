import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

// MARK: - Permission status

private enum PermStatus: Equatable {
    case granted
    case undetermined  // not yet asked → trigger system dialog
    case denied        // user denied → open System Settings

    var isGranted: Bool { self == .granted }
}

// Accessibility and Screen Recording are binary (no notDetermined API)
private func checkAccessibility()   -> PermStatus { AXIsProcessTrusted() ? .granted : .denied }
private func checkScreenRecording() -> PermStatus { CGPreflightScreenCaptureAccess() ? .granted : .denied }

private func checkMicrophone() -> PermStatus {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:    return .granted
    case .notDetermined: return .undetermined
    default:             return .denied
    }
}

private func checkSpeech() -> PermStatus {
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:    return .granted
    case .notDetermined: return .undetermined
    default:             return .denied
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let status: PermStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                    Text(title)
                        .foregroundColor(.primary)
                    Spacer()
                    if !status.isGranted {
                        Text(status == .undetermined
                             ? "settings.permissions.allow"
                             : "settings.permissions.grant")
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

    private var dotColor: Color {
        switch status {
        case .granted:      return .green
        case .undetermined: return .yellow
        case .denied:       return Color.secondary.opacity(0.35)
        }
    }
}

// MARK: - General pane

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
                    .onChange(of: draft.launchAtLogin) { _, enabled in
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
                .onChange(of: draft.appLanguage) { _, lang in
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
                        onSave(draft) // flush pending settings before restart
                        let url = Bundle.main.bundleURL
                        let config = NSWorkspace.OpenConfiguration()
                        config.createsNewApplicationInstance = true
                        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                            guard error == nil else { return } // keep running if relaunch failed
                            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
                        }
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
                    action: openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                )
                PermissionRow(
                    title: "settings.permissions.microphone",
                    description: "settings.permissions.microphone.description",
                    status: permMicrophone,
                    action: {
                        if permMicrophone == .undetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in
                                DispatchQueue.main.async { refreshPermissions() }
                            }
                        } else {
                            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")()
                        }
                    }
                )
                PermissionRow(
                    title: "settings.permissions.screen_recording",
                    description: "settings.permissions.screen_recording.description",
                    status: permScreenRecording,
                    action: openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
                )
                PermissionRow(
                    title: "settings.permissions.speech_recognition",
                    description: "settings.permissions.speech_recognition.description",
                    status: permSpeech,
                    action: {
                        if permSpeech == .undetermined {
                            SFSpeechRecognizer.requestAuthorization { _ in
                                DispatchQueue.main.async { refreshPermissions() }
                            }
                        } else {
                            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")()
                        }
                    }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        permAccessibility   = checkAccessibility()
        permMicrophone      = checkMicrophone()
        permScreenRecording = checkScreenRecording()
        permSpeech          = checkSpeech()
    }

    private func openSystemSettings(_ urlString: String) -> () -> Void {
        { if let u = URL(string: urlString) { NSWorkspace.shared.open(u) } }
    }
}
