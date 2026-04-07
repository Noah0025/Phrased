import SwiftUI
import LocalAuthentication

// MARK: - Navigation items

enum SettingsSection: String, CaseIterable, Identifiable {
    case model      = "model"
    case audio      = "audio"
    case hotkey     = "hotkey"
    case templates  = "templates"
    case vocabulary = "vocabulary"
    case history    = "history"
    case general    = "general"
    case about      = "about"

    var id: String { rawValue }

    var localizedName: LocalizedStringKey {
        switch self {
        case .model:      return "settings.section.language_model"
        case .audio:      return "settings.section.audio_speech"
        case .hotkey:     return "settings.section.hotkey"
        case .templates:  return "settings.section.prompt_templates"
        case .vocabulary: return "settings.section.text_substitution"
        case .history:    return "settings.section.history"
        case .general:    return "settings.section.general"
        case .about:      return "settings.section.about"
        }
    }

    var icon: String {
        switch self {
        case .model:      return "cpu"
        case .audio:      return "waveform"
        case .hotkey:     return "keyboard"
        case .templates:  return "text.badge.plus"
        case .vocabulary: return "text.word.spacing"
        case .history:    return "clock"
        case .general:    return "gearshape"
        case .about:      return "info.circle"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @State var draft: PhrasedSettings
    @State var vocabWords: [VocabEntry] = VocabularyStore.loadOrDefault().words
    @State var selection: SettingsSection? = .general
    @State var deleteActiveProfileIndex: Int? = nil
    @State var expandedLLMProfileIDs: Set<UUID> = []
    @State var editingKeyLLMProfileID: UUID? = nil
    @State var llmKeyVisible = false
    @State var llmKeyBackup = ""
    @State var llmScanning = false
    @State var llmScanResults: [ServiceScanResult] = []
    @State var llmInstalledNotRunning: [String] = []
    @State var llmScanDone = false
    @State var expandedASRProfileIDs: Set<UUID> = []
    @State var expandedTemplateIDs: Set<String> = []
    @State var editingKeyASRProfileID: UUID? = nil
    @State var asrKeyVisible = false
    @State var asrKeyBackup = ""
    @State var asrScanning = false
    @State var asrScanResults: [ServiceScanResult] = []
    @State var asrInstalledNotRunning: [String] = []
    @State var asrScanDone = false
    @State var showASRAdvisor = false
    @State var advisorRegion = ""
    @State var advisorLanguage = ""
    @State var advisorResult = ""
    @State var advisorStreaming = false
    @State var advisorStreamTask: Task<Void, Never>?
    @State var saveTask: DispatchWorkItem?
    @State var hasUnsavedChanges = false
    let onSave: (PhrasedSettings) -> Void
    let onOpenHistory: (() -> Void)?
    let onExportHistory: (() -> Void)?

    init(settings: PhrasedSettings,
         onSave: @escaping (PhrasedSettings) -> Void,
         onOpenHistory: (() -> Void)? = nil,
         onExportHistory: (() -> Void)? = nil) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
        self.onOpenHistory = onOpenHistory
        self.onExportHistory = onExportHistory
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.localizedName, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            // Detail pane
            Group {
                switch selection {
                case .model:      modelPane
                case .audio:      audioPane
                case .hotkey:     hotkeyPane
                case .templates:  templatesPane
                case .vocabulary: vocabularyPane
                case .history:    historyPane
                case .general:    generalPane
                case .about:      aboutPane
                case nil:         modelPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .onChange(of: draft) { newValue in
            hasUnsavedChanges = true
            saveTask?.cancel()
            let task = DispatchWorkItem { [newValue] in
                onSave(newValue)
                hasUnsavedChanges = false
            }
            saveTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: task)
        }
        .onDisappear {
            flushPendingSave()
            advisorStreamTask?.cancel()
            advisorStreamTask = nil
        }
    }

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        onSave(draft)
    }

    // generalPane — see Panes/GeneralSettingsPane.swift
    // aboutPane — see Panes/AboutSettingsPane.swift
    // modelPane — see Panes/ModelSettingsPane.swift
    // audioPane — see Panes/AudioSettingsPane.swift
    // templatesPane — see Panes/TemplatesSettingsPane.swift

    func profileField(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey? = nil) -> some View {
        HStack {
            Text(label).font(PhrasedFont.secondary).frame(width: 50, alignment: .trailing)
            TextField("", text: text, prompt: prompt.map { Text($0) })
                .textFieldStyle(.roundedBorder)
                .font(PhrasedFont.secondary)
        }
    }

    @ViewBuilder
    func profileFieldRow<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(PhrasedFont.secondary)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .leading)
            content()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Shared key row

    /// 通用 API Key 行，供 ASR 和 LLM 配置卡片复用。
    @ViewBuilder
    func profileKeyRow(
        key: Binding<String>,
        isEditing: Bool,
        keyVisible: Bool,
        optional: Bool = false,
        configureAccessibilityLabel: String? = nil,
        onToggleVisible: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onEdit: @escaping () -> Void
    ) -> some View {
        ProfileKeyRowView(
            key: key,
            isEditing: isEditing,
            keyVisible: keyVisible,
            optional: optional,
            configureAccessibilityLabel: configureAccessibilityLabel,
            onToggleVisible: onToggleVisible,
            onSave: onSave,
            onCancel: onCancel,
            onEdit: onEdit
        )
    }

    /// 触发系统验证，成功后执行 onSuccess。
    func authenticateKey(onSuccess: @escaping () -> Void) {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "settings.key.auth_reason")) { success, _ in
                if success {
                    DispatchQueue.main.async {
                        // Touch ID 对话框会让 settings 窗口失去 key 状态，
                        // borderedProminent 按钮在非 key window 下会隐藏，需要重新激活。
                        NSApp.activate(ignoringOtherApps: true)
                        onSuccess()
                    }
                }
            }
        } else {
            onSuccess()
        }
    }

    struct ServiceScanResult: Identifiable {
        let id = UUID()
        let name: String
        let baseURL: String
        let model: String
    }

    // vocabularyPane — see Panes/VocabularySettingsPane.swift
    // historyPane — see Panes/HistorySettingsPane.swift
    // ASRAdvisorSheet — see Panes/AudioSettingsPane.swift
}

// MARK: - ProfileKeyRowView

/// 通用 API Key 行。使用独立 View struct 以支持 @FocusState。
///
/// 状态机：
/// - 空 + 未聚焦 → 仅 SecureField，无按钮
/// - 聚焦或正在输入 → SecureField + 眼睛 + 保存（有内容时）
/// - 有内容 + 未聚焦 + 非编辑中 → 锁定：••••• + 配置按钮
/// - 编辑中（auth 解锁后）→ SecureField + 眼睛 + 保存 + 取消
private struct ProfileKeyRowView: View {
    @Binding var key: String
    var isEditing: Bool
    var keyVisible: Bool
    var optional: Bool
    var configureAccessibilityLabel: String?
    var onToggleVisible: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    var onEdit: () -> Void

    /// 同一渲染周期内同时更新 key 和 hasUnsavedInput，避免竞态导致误触发锁定。
    @State var hasUnsavedInput = false

    var editableKey: Binding<String> {
        Binding(
            get: { key },
            set: { newValue in
                key = newValue
                if !newValue.isEmpty && !isEditing {
                    hasUnsavedInput = true
                }
            }
        )
    }

    var body: some View {
        let hasContent = !key.isEmpty
        let locked = hasContent && !isEditing && !hasUnsavedInput
        let keyPrompt = optional ? String(localized: "settings.key.prompt.optional") : String(localized: "settings.key.prompt.required")

        HStack(spacing: 8) {
            Text("settings.key.label")
                .font(PhrasedFont.secondary)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .leading)

            if locked {
                Text("settings.key.configured_masked")
                    .font(PhrasedFont.secondary).foregroundColor(.secondary)
                Spacer()
                Button("settings.button.configure") { onEdit() }
                    .buttonStyle(.bordered).controlSize(.mini)
                    .accessibilityLabel(configureAccessibilityLabel ?? String(localized: "settings.button.configure"))
            } else {
                Group {
                    if keyVisible {
                        TextField("", text: editableKey, prompt: Text(keyPrompt))
                    } else {
                        SecureField("", text: editableKey, prompt: Text(keyPrompt))
                    }
                }
                .font(PhrasedFont.secondary)

                if hasContent {
                    Button { onToggleVisible() } label: {
                        Image(systemName: keyVisible ? "eye.slash" : "eye")
                            .font(PhrasedFont.caption).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isEditing {
                    Button("settings.button.done") {
                        hasUnsavedInput = false
                        onSave()
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    Button("app.button.cancel") {
                        hasUnsavedInput = false
                        onCancel()
                    }
                    .buttonStyle(.plain).controlSize(.mini).foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
