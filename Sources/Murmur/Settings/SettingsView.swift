import SwiftUI
import LocalAuthentication

// MARK: - Navigation items

private enum SettingsSection: String, CaseIterable, Identifiable {
    case model      = "语言模型"
    case audio      = "音频与语音"
    case hotkey     = "快捷键"
    case templates  = "提示词模板"
    case vocabulary = "热词"
    case history    = "历史记录"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .model:      return "cpu"
        case .audio:      return "waveform"
        case .hotkey:     return "keyboard"
        case .templates:  return "text.badge.plus"
        case .vocabulary: return "text.word.spacing"
        case .history:    return "clock"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @State private var draft: MurmurSettings
    @State private var vocabWords: [VocabEntry] = VocabularyStore.loadOrDefault().words
    @State private var selection: SettingsSection? = .model
    @State private var deleteActiveProfileIndex: Int? = nil
    @State private var expandedLLMProfileIDs: Set<UUID> = []
    @State private var editingKeyLLMProfileID: UUID? = nil
    @State private var llmKeyVisible = false
    @State private var llmKeyBackup = ""
    @State private var llmScanning = false
    @State private var llmScanResults: [LLMScanResult] = []
    @State private var llmInstalledNotRunning: [String] = []
    @State private var llmScanDone = false
    @State private var expandedASRProfileIDs: Set<UUID> = []
    @State private var expandedTemplateIDs: Set<String> = []
    @State private var editingKeyASRProfileID: UUID? = nil
    @State private var asrKeyVisible = false
    @State private var asrKeyBackup = ""
    @State private var asrScanning = false
    @State private var asrScanResults: [ASRScanResult] = []
    @State private var asrInstalledNotRunning: [String] = []
    @State private var asrScanDone = false
    @State private var showASRAdvisor = false
    @State private var advisorRegion = ""
    @State private var advisorLanguage = ""
    @State private var advisorResult = ""
    @State private var advisorStreaming = false
    @State private var advisorStreamTask: Task<Void, Never>?
    @State private var saveTask: DispatchWorkItem?
    @State private var hasUnsavedChanges = false
    private let onSave: (MurmurSettings) -> Void

    init(settings: MurmurSettings, onSave: @escaping (MurmurSettings) -> Void) {
        _draft = State(initialValue: settings)
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
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

    // MARK: - Model


    private var modelPane: some View {
        Form {
            Section("语言模型") {
                Picker("当前配置", selection: $draft.selectedProfileID) {
                    ForEach(draft.localProfiles) { p in
                        Text(p.name.isEmpty ? "未命名" : p.name).tag(p.id)
                    }
                }
            }

            Section("高级设置") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("支持任意兼容 OpenAI 格式的语言模型服务，本地或云端均可。本地模型推荐使用 7B 及以上参数量的模型，云端模型须填写有效的服务地址、模型名称和 API Key。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    ForEach(draft.localProfiles.indices, id: \.self) { idx in
                        llmProfileRow(index: idx)
                    }

                    // 扫描结果：运行中的服务（可添加）
                    if !llmScanResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("检测到以下可用的模型：")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                if llmScanResults.count > 1 {
                                    Button("全部添加") {
                                        for r in llmScanResults where !draft.localProfiles.contains(where: { $0.baseURL == r.baseURL && $0.selectedModel == r.model }) {
                                            draft.localProfiles.append(LLMProfile(name: r.name, baseURL: r.baseURL, selectedModel: r.model))
                                        }
                                        llmScanResults = []
                                        llmScanDone = false
                                    }
                                    .buttonStyle(.bordered).controlSize(.mini)
                                }
                            }
                            let limited = llmScanResultsLimited
                            ForEach(limited.visible) { result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name).font(.system(size: 12, weight: .medium))
                                        Text(result.baseURL).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if draft.localProfiles.contains(where: { $0.baseURL == result.baseURL && $0.selectedModel == result.model }) {
                                        Text("已添加").font(.caption).foregroundColor(.secondary)
                                    } else {
                                        Button("添加") {
                                            draft.localProfiles.append(LLMProfile(name: result.name, baseURL: result.baseURL, selectedModel: result.model))
                                        }
                                        .buttonStyle(.bordered).controlSize(.mini)
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            if limited.hiddenCount > 0 {
                                Text("还有 \(limited.hiddenCount) 个模型未显示，点击「全部添加」可一并导入。")
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // 已安装但未运行
                    if !llmInstalledNotRunning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已安装但未运行，启动后重新扫描：")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(llmInstalledNotRunning, id: \.self) { name in
                                Text("• \(name)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, llmScanResults.isEmpty ? 4 : 0)
                    }

                    HStack(spacing: 8) {
                        Button("扫描本地模型") {
                            scanLocalLLMServices()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(llmScanning)
                        .overlay {
                            if llmScanning {
                                ProgressView().scaleEffect(0.5).offset(x: -4)
                            }
                        }

                        Button("添加云端模型") {
                            let p = LLMProfile(name: "", baseURL: "https://")
                            draft.localProfiles.append(p)
                            expandedLLMProfileIDs.insert(p.id)
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
                .alert("删除当前使用中的配置？", isPresented: Binding(
                    get: { deleteActiveProfileIndex != nil },
                    set: { if !$0 { deleteActiveProfileIndex = nil } }
                )) {
                    Button("确认删除", role: .destructive) {
                        if let idx = deleteActiveProfileIndex, idx < draft.localProfiles.count {
                            _ = expandedLLMProfileIDs.remove(draft.localProfiles[idx].id)
                            draft.localProfiles.remove(at: idx)
                            if let first = draft.localProfiles.first {
                                draft.selectedProfileID = first.id
                            }
                        }
                        deleteActiveProfileIndex = nil
                    }
                    Button("取消", role: .cancel) { deleteActiveProfileIndex = nil }
                } message: {
                    Text("该配置当前正在使用中，删除后将自动切换到其他配置。")
                }
                .alert("未检测到可用的本地模型", isPresented: Binding(
                    get: { llmScanDone && llmScanResults.isEmpty && llmInstalledNotRunning.isEmpty && !llmScanning },
                    set: { if !$0 { llmScanDone = false } }
                )) {
                    Button("取消", role: .cancel) { llmScanDone = false }
                    Button("手动添加") {
                        llmScanDone = false
                        let p = LLMProfile(name: "", baseURL: "http://localhost:")
                        draft.localProfiles.append(p)
                        expandedLLMProfileIDs.insert(p.id)
                    }
                } message: {
                    Text("未在常见端口检测到运行中的服务，请确认服务已启动，或手动填写配置。")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("LLM 配置")
    }

    @ViewBuilder
    private func llmProfileRow(index: Int) -> some View {
        if index < draft.localProfiles.count {
        let profile = draft.localProfiles[index]
        let isExpanded = expandedLLMProfileIDs.contains(profile.id)
        VStack(spacing: 0) {
            // ── 折叠态（一级）──
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        _ = expandedLLMProfileIDs.remove(profile.id)
                        editingKeyLLMProfileID = nil
                    } else {
                        expandedLLMProfileIDs.insert(profile.id)
                    }
                }
            } label: {
                HStack {
                    Text(profile.name.isEmpty ? "未命名" : profile.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    let llmCategory = (profile.baseURL.hasPrefix("http://localhost") || profile.baseURL.hasPrefix("http://127.")) ? "本地模型" : "云端模型"
                    Text(llmCategory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06 as Double))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Button {
                        let isActive = profile.id == draft.selectedProfileID
                        if isActive && draft.localProfiles.count > 1 {
                            deleteActiveProfileIndex = index
                        } else {
                            _ = expandedLLMProfileIDs.remove(profile.id)
                            draft.localProfiles.remove(at: index)
                            draft.selectedProfileID = draft.localProfiles.first?.id ?? UUID()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(MurmurFont.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("删除")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(MurmurFont.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── 展开态（二级）──
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    let isLocal = draft.localProfiles[index].baseURL.hasPrefix("http://localhost") ||
                                  draft.localProfiles[index].baseURL.hasPrefix("http://127.")
                    profileFieldRow(label: "名称", content: {
                        TextField("", text: $draft.localProfiles[index].name, prompt: Text("模型标签"))
                            .font(MurmurFont.secondary)
                    })
                    Divider()
                    profileFieldRow(label: "地址", content: {
                        TextField("", text: $draft.localProfiles[index].baseURL,
                                  prompt: Text(isLocal ? "http://localhost:11434" : "https://api.openai.com/v1"))
                            .font(MurmurFont.secondary)
                    })
                    Divider()
                    profileFieldRow(label: "模型", content: {
                        TextField("", text: $draft.localProfiles[index].selectedModel,
                                  prompt: Text(isLocal ? "qwen2.5:7b" : "gpt-4o-mini"))
                            .font(MurmurFont.secondary)
                    })
                    Divider()
                    llmKeyRow(index: index, profile: profile)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12 as Double), lineWidth: 1))
        .id(profile.id)
        }
    }

    @ViewBuilder
    private func llmKeyRow(index: Int, profile: LLMProfile) -> some View {
        let isLocal = draft.localProfiles[index].baseURL.hasPrefix("http://localhost") ||
                      draft.localProfiles[index].baseURL.hasPrefix("http://127.")
        profileKeyRow(
            key: $draft.localProfiles[index].apiKey,
            isEditing: editingKeyLLMProfileID == profile.id,
            keyVisible: llmKeyVisible,
            optional: isLocal,
            onToggleVisible: { llmKeyVisible.toggle() },
            onSave: { editingKeyLLMProfileID = nil; llmKeyVisible = false },
            onCancel: {
                draft.localProfiles[index].apiKey = llmKeyBackup
                editingKeyLLMProfileID = nil; llmKeyVisible = false
            },
            onEdit: {
                authenticateKey {
                    llmKeyBackup = draft.localProfiles[index].apiKey
                    llmKeyVisible = false
                    editingKeyLLMProfileID = profile.id
                }
            }
        )
    }

    // MARK: - Audio

    private var audioPane: some View {
        Form {
            Section("默认输入源") {
                Picker("输入源", selection: $draft.audioSource) {
                    Text("系统音频").tag("systemAudio")
                    Text("麦克风").tag("microphone")
                }
                Text(draft.audioSource == "systemAudio" ? "需要屏幕录制权限。" : "需要麦克风权限。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section("语音识别模型") {
                Picker("当前配置", selection: $draft.selectedASRProfileID) {
                    ForEach(draft.asrProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }

            Section("高级设置") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("支持 macOS 内置识别及任意兼容 OpenAI 格式的语音识别服务，本地或云端均可。使用本地语音识别服务前须确认服务已运行，云端语音识别服务须填写有效的服务地址、语音识别模型名称和 API Key。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)

                    // 已有配置
                    ForEach(draft.asrProfiles.indices, id: \.self) { idx in
                        asrProfileRow(index: idx)
                    }

                    // 扫描结果：运行中的服务（可添加）
                    if !asrScanResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("检测到以下可用的语音识别服务：")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                if asrScanResults.count > 1 {
                                    Button("全部添加") {
                                        for r in asrScanResults where !draft.asrProfiles.contains(where: { $0.baseURL == r.baseURL }) {
                                            draft.asrProfiles.append(ASRProfile(name: r.name, providerType: "api", baseURL: r.baseURL, model: r.model))
                                        }
                                        asrScanResults = []
                                        asrScanDone = false
                                    }
                                    .buttonStyle(.bordered).controlSize(.mini)
                                }
                            }
                            ForEach(asrScanResults) { result in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name).font(.system(size: 12, weight: .medium))
                                        Text(result.baseURL).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if draft.asrProfiles.contains(where: { $0.baseURL == result.baseURL }) {
                                        Text("已添加").font(.caption).foregroundColor(.secondary)
                                    } else {
                                        Button("添加") {
                                            draft.asrProfiles.append(ASRProfile(name: result.name, providerType: "api", baseURL: result.baseURL, model: result.model))
                                        }
                                        .buttonStyle(.bordered).controlSize(.mini)
                                    }
                                }
                                .padding(8)
                                .background(Color.primary.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .padding(.top, 4)
                    }

                    // 已安装但未运行
                    if !asrInstalledNotRunning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已安装但未运行，启动后重新扫描：")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(asrInstalledNotRunning, id: \.self) { name in
                                Text("• \(name)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, asrScanResults.isEmpty ? 4 : 0)
                    }

                    HStack(spacing: 8) {
                        Button("扫描本地语音识别服务") {
                            scanLocalASRServices()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(asrScanning)

                        .overlay {
                            if asrScanning {
                                ProgressView().scaleEffect(0.5).offset(x: -4)
                            }
                        }

                        Button("添加云端语音识别服务") {
                            let newProfile = ASRProfile(name: "", providerType: "api",
                                                        baseURL: "https://")
                            draft.asrProfiles.append(newProfile)
                            expandedASRProfileIDs.insert(newProfile.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("语音识别模型建议") {
                            advisorResult = ""
                            showASRAdvisor = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .sheet(isPresented: $showASRAdvisor) {
                        ASRAdvisorSheet(
                            region: $advisorRegion,
                            language: $advisorLanguage,
                            result: $advisorResult,
                            isStreaming: $advisorStreaming,
                            hardwareInfo: hardwareInfo(),
                            onAdd: { name, baseURL, model in
                                if !draft.asrProfiles.contains(where: { $0.baseURL == baseURL }) {
                                    draft.asrProfiles.append(ASRProfile(
                                        name: name, providerType: "api",
                                        baseURL: baseURL, model: model
                                    ))
                                }
                            },
                            onAsk: { askASRAdvisor() }
                        )
                    }
                    .padding(.top, 4)
                    .alert("未检测到可用的本地语音识别服务", isPresented: Binding(
                        get: { asrScanDone && asrScanResults.isEmpty && asrInstalledNotRunning.isEmpty && !asrScanning },
                        set: { if !$0 { asrScanDone = false } }
                    )) {
                        Button("取消", role: .cancel) { asrScanDone = false }
                        Button("手动添加") {
                            asrScanDone = false
                            let newProfile = ASRProfile(name: "", providerType: "api",
                                                        baseURL: "http://localhost:")
                            draft.asrProfiles.append(newProfile)
                            expandedASRProfileIDs.insert(newProfile.id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("音频")
    }


    private func asrCategory(_ profile: ASRProfile) -> String {
        if profile.providerType == "sfspeech" { return "macOS 内置" }
        let isLocal = profile.baseURL.hasPrefix("http://localhost") || profile.baseURL.hasPrefix("http://127.")
        return isLocal ? "本地模型" : "云端模型"
    }

    @ViewBuilder
    private func asrProfileRow(index: Int) -> some View {
        if index < draft.asrProfiles.count {
            let profile = draft.asrProfiles[index]
            let isExpanded = expandedASRProfileIDs.contains(profile.id)
            let isSFSpeech = profile.id == ASRProfile.builtinSFSpeech.id

            VStack(spacing: 0) {
                // ── 折叠态（一级）──
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            _ = expandedASRProfileIDs.remove(profile.id)
                            editingKeyASRProfileID = nil
                        } else {
                            expandedASRProfileIDs.insert(profile.id)
                        }
                    }
                } label: {
                    HStack {
                        Text(profile.name.isEmpty ? "未命名" : profile.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(asrCategory(profile))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(MurmurFont.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // ── 展开态（二级）──
                if isExpanded {
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        if isSFSpeech {
                            // macOS 内置：只读
                            VStack(alignment: .leading, spacing: 6) {
                                Text("macOS 系统内置语音识别，首次使用时会自动请求授权，无需手动配置。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Apple 芯片：本地识别，离线可用，音频不上传。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("• Intel 处理器：通过 Apple 服务器识别，需要网络，音频会上传至 Apple。")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        } else {
                            let isLocal = asrCategory(draft.asrProfiles[index]) == "本地模型"
                            profileFieldRow(label: "名称", content: {
                                TextField("", text: $draft.asrProfiles[index].name, prompt: Text("模型标签"))
                                    .font(MurmurFont.secondary)
                            })
                            Divider()
                            profileFieldRow(label: "地址", content: {
                                TextField("", text: $draft.asrProfiles[index].baseURL,
                                          prompt: Text(isLocal ? "http://localhost:8000" : "https://api.example.com/v1"))
                                    .font(MurmurFont.secondary)
                            })
                            Divider()
                            profileFieldRow(label: "语音识别模型", content: {
                                TextField("", text: $draft.asrProfiles[index].model,
                                          prompt: Text(isLocal ? "whisper-1" : "whisper-large-v3"))
                                    .font(MurmurFont.secondary)
                            })
                            Divider()
                            asrKeyRow(index: index, profile: profile, optional: isLocal)
                            Divider()
                            HStack {
                                Button("删除") {
                                    let id = profile.id
                                    withAnimation { _ = expandedASRProfileIDs.remove(profile.id) }
                                    draft.asrProfiles.remove(at: index)
                                    if draft.selectedASRProfileID == id {
                                        draft.selectedASRProfileID = draft.asrProfiles.first?.id ?? ASRProfile.builtinSFSpeech.id
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(.red)

                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12 as Double), lineWidth: 1))
            .id(profile.id)
        }
    }

    @ViewBuilder
    private func profileFieldRow<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(MurmurFont.secondary)
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
    private func profileKeyRow(
        key: Binding<String>,
        isEditing: Bool,
        keyVisible: Bool,
        optional: Bool = false,
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
            onToggleVisible: onToggleVisible,
            onSave: onSave,
            onCancel: onCancel,
            onEdit: onEdit
        )
    }

    /// 触发系统验证，成功后执行 onSuccess。
    private func authenticateKey(onSuccess: @escaping () -> Void) {
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "验证身份以访问 API Key") { success, _ in
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

    @ViewBuilder
    private func asrKeyRow(index: Int, profile: ASRProfile, optional: Bool = false) -> some View {
        profileKeyRow(
            key: $draft.asrProfiles[index].apiKey,
            isEditing: editingKeyASRProfileID == profile.id,
            keyVisible: asrKeyVisible,
            optional: optional,
            onToggleVisible: { asrKeyVisible.toggle() },
            onSave: { editingKeyASRProfileID = nil; asrKeyVisible = false },
            onCancel: {
                draft.asrProfiles[index].apiKey = asrKeyBackup
                editingKeyASRProfileID = nil; asrKeyVisible = false
            },
            onEdit: {
                authenticateKey {
                    asrKeyBackup = draft.asrProfiles[index].apiKey
                    asrKeyVisible = false
                    editingKeyASRProfileID = profile.id
                }
            }
        )
    }

    // MARK: - Local scan helpers

    /// Run a command and return true if exit code is 0.
    /// Note: uses waitUntilExit() — acceptable here because commands are fast (which/brew list)
    /// and called only during user-initiated scans inside a Task.
    private func shellCheck(_ args: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = args
            p.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
            p.standardOutput = Pipe(); p.standardError = Pipe()
            p.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus == 0)
            }
            do {
                try p.run()
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Return true if <appName>.app exists in /Applications or ~/Applications.
    private func appInstalled(_ appName: String) -> Bool {
        let fm = FileManager.default
        let paths = [
            "/Applications/\(appName).app",
            "\(NSHomeDirectory())/Applications/\(appName).app"
        ]
        return paths.contains { fm.fileExists(atPath: $0) }
    }

    // MARK: - Local ASR Scan

    struct ASRScanResult: Identifiable {
        let name: String
        let baseURL: String
        let model: String
        var id: String { baseURL + "/" + model }
    }

    struct LLMScanResult: Identifiable {
        let name: String    // model name (or service name if no models)
        let baseURL: String
        let model: String
        var id: String { baseURL + "/" + model }
    }

    private var llmScanResultsLimited: (visible: [LLMScanResult], hiddenCount: Int) {
        let maxPerHost = 5
        var seen: [String: Int] = [:]
        var visible: [LLMScanResult] = []
        var hidden = 0
        for r in llmScanResults {
            let count = seen[r.baseURL, default: 0]
            if count < maxPerHost {
                visible.append(r)
                seen[r.baseURL] = count + 1
            } else {
                hidden += 1
            }
        }
        return (visible, hidden)
    }

    /// Known packages: (pip package, brew formula, display name, default URL, default model)
    private let knownPackages: [(pip: String?, brew: String?, name: String, port: Int, model: String)] = [
        ("faster-whisper-server", nil,          "faster-whisper-server", 8000, "Systran/faster-whisper-small"),
        (nil,                     "whisper-cpp", "whisper.cpp",           8080, "base"),
        ("openedai-speech",       nil,           "openedai-speech",       8000, "tts-1"),
        ("whisperx",              nil,           "whisperX",              8001, "large-v3"),
    ]

    /// Ports to probe for any running OpenAI-compatible ASR service
    private let probePorts: [Int] = [8000, 8001, 8080, 8765, 9000, 5000]

    /// Known LLM services with install detection info
    private let knownLLMPackages: [(binary: String?, appName: String?, brew: String?, name: String, port: Int)] = [
        ("ollama", nil,         "ollama",    "Ollama",    11434),
        (nil,      "LM Studio", nil,         "LM Studio", 1234),
        (nil,      "Jan",       nil,         "Jan",       1337),
        (nil,      nil,         "llama.cpp", "llama.cpp", 8080),
    ]

    /// All ports to probe (includes generic catch-all port 8000)
    private let knownLLMPorts: [(port: Int, name: String)] = [
        (11434, "Ollama"),
        (1234,  "LM Studio"),
        (1337,  "Jan"),
        (8080,  "llama.cpp"),
        (8000,  "本地语音识别服务"),
    ]

    private func scanLocalLLMServices() {
        llmScanning = true
        llmScanResults = []
        llmInstalledNotRunning = []
        llmScanDone = false

        Task {
            // 1. Check installed packages
            var installedByPort: [Int: String] = [:]  // port → service name

            for pkg in knownLLMPackages {
                var installed = false
                if let binary = pkg.binary  { installed = await shellCheck(["which", binary]) }
                if !installed, let app = pkg.appName { installed = appInstalled(app) }
                if !installed, let brew = pkg.brew   { installed = await shellCheck(["brew", "list", brew]) }
                if installed { installedByPort[pkg.port] = pkg.name }
            }

            // 2. Probe all known ports concurrently, parse model list
            var portModels: [Int: [String]] = [:]  // port → models (present = running)
            await withTaskGroup(of: (Int, [String]?).self) { group in
                for entry in knownLLMPorts {
                    group.addTask {
                        let base = "http://localhost:\(entry.port)"
                        guard let url = URL(string: "\(base)/v1/models") else { return (entry.port, nil) }
                        var req = URLRequest(url: url, timeoutInterval: 1.5)
                        req.httpMethod = "GET"
                        guard let (data, _) = try? await URLSession.shared.data(for: req),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let list = json["data"] as? [[String: Any]] else { return (entry.port, nil) }
                        let models = list.compactMap { $0["id"] as? String }.sorted()
                        return (entry.port, models)
                    }
                }
                for await (port, models) in group {
                    if let models { portModels[port] = models }
                }
            }

            // 3. Merge: known installed → running or not-running; unknown running → generic
            var results: [LLMScanResult] = []
            var notRunning: [String] = []
            var handledPorts: Set<Int> = []

            for (port, name) in installedByPort {
                if let models = portModels[port] {
                    if models.isEmpty {
                        results.append(LLMScanResult(name: name, baseURL: "http://localhost:\(port)", model: ""))
                    } else {
                        for model in models {
                            results.append(LLMScanResult(name: model, baseURL: "http://localhost:\(port)", model: model))
                        }
                    }
                    handledPorts.insert(port)
                } else {
                    notRunning.append(name)
                }
            }

            // Any port that responded but isn't a known installed package
            for (port, models) in portModels where !handledPorts.contains(port) {
                let name = knownLLMPorts.first(where: { $0.port == port })?.name ?? "本地服务（端口 \(port)）"
                if models.isEmpty {
                    results.append(LLMScanResult(name: name, baseURL: "http://localhost:\(port)", model: ""))
                } else {
                    for model in models {
                        results.append(LLMScanResult(name: model, baseURL: "http://localhost:\(port)", model: model))
                    }
                }
            }

            await MainActor.run {
                self.llmScanResults = results.filter { r in
                    !self.draft.localProfiles.contains(where: { $0.baseURL == r.baseURL && $0.selectedModel == r.model })
                }
                self.llmInstalledNotRunning = notRunning
                self.llmScanning = false
                self.llmScanDone = true
            }
        }
    }

    private func scanLocalASRServices() {
        asrScanning = true
        asrScanResults = []
        asrInstalledNotRunning = []
        asrScanDone = false

        Task {
            // 1. Check installed packages
            var installedByPort: [Int: String] = [:]  // port → name
            var installedByName: [String: (port: Int, model: String)] = [:]

            for pkg in knownPackages {
                var installed = false
                if let pip = pkg.pip { installed = await shellCheck(["pip3", "show", pip]) }
                if !installed, let brew = pkg.brew { installed = await shellCheck(["brew", "list", brew]) }
                if installed {
                    installedByPort[pkg.port] = pkg.name
                    installedByName[pkg.name] = (pkg.port, pkg.model)
                }
            }

            // 2. Probe ports for running services via GET /v1/models
            var runningPorts: Set<Int> = []
            await withTaskGroup(of: (Int, Bool).self) { group in
                for port in probePorts {
                    group.addTask {
                        guard let url = URL(string: "http://localhost:\(port)/v1/models") else {
                            return (port, false)
                        }
                        var req = URLRequest(url: url, timeoutInterval: 1.5)
                        req.httpMethod = "GET"
                        let ok = (try? await URLSession.shared.data(for: req))
                            .map { _, resp in (resp as? HTTPURLResponse)?.statusCode == 200 } ?? false
                        return (port, ok)
                    }
                }
                for await (port, ok) in group {
                    if ok { runningPorts.insert(port) }
                }
            }

            // 3. Merge results
            var running: [ASRScanResult] = []
            var notRunning: [String] = []
            var handledPorts: Set<Int> = []

            // Known package + running
            for (name, info) in installedByName {
                if runningPorts.contains(info.port) {
                    running.append(ASRScanResult(name: name, baseURL: "http://localhost:\(info.port)", model: info.model))
                    handledPorts.insert(info.port)
                } else {
                    notRunning.append(name)
                }
            }

            // Running on unknown port → generic
            for port in runningPorts.subtracting(handledPorts) {
                running.append(ASRScanResult(name: "本地语音识别服务（端口 \(port)）", baseURL: "http://localhost:\(port)", model: ""))
            }

            await MainActor.run {
                self.asrScanResults = running.filter { r in
                    !self.draft.asrProfiles.contains(where: { $0.baseURL == r.baseURL })
                }
                self.asrInstalledNotRunning = notRunning
                self.asrScanning = false
                self.asrScanDone = true
            }
        }
    }

    // MARK: - ASR Advisor

    private func hardwareInfo() -> String {
        var memSize: UInt64 = 0
        var memLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memLen, nil, 0)
        let ramGB = memSize / (1024 * 1024 * 1024)

        var cpuBuf = [CChar](repeating: 0, count: 256)
        var cpuLen = cpuBuf.count
        sysctlbyname("machdep.cpu.brand_string", &cpuBuf, &cpuLen, nil, 0)
        let cpu = String(cString: cpuBuf)

        // Apple chip doesn't expose brand_string via machdep; check arch instead
        var archBuf = [CChar](repeating: 0, count: 64)
        var archLen = archBuf.count
        sysctlbyname("hw.machine", &archBuf, &archLen, nil, 0)
        let arch = String(cString: archBuf)
        let chipDesc = cpu.isEmpty ? (arch.contains("arm") ? "Apple 芯片" : "未知") : cpu
        return "芯片：\(chipDesc)，内存：\(ramGB) GB"
    }

    private func askASRAdvisor() {
        advisorStreamTask?.cancel()
        advisorStreaming = true
        advisorResult = ""
        let hw = hardwareInfo()
        var memSize: UInt64 = 0; var memLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memLen, nil, 0)
        let ramGB = memSize / (1024 * 1024 * 1024)
        let region = advisorRegion.isEmpty ? "未指定" : advisorRegion
        let lang = advisorLanguage.isEmpty ? "未指定" : advisorLanguage
        let prompt = """
你是语音识别模型选型顾问。根据以下信息推荐语音识别方案：

设备：\(hw)
地区：\(region)
语言：\(lang)

格式要求（严格按此输出，不要多余说明）：

【本地模型】（推荐 2-3 个）

方案名：
API 地址：（localhost 地址）
模型名：
推荐理由：（一句话）

【云端模型】（推荐 2-3 个）

方案名：
API 地址：（完整 URL）
模型名：
推荐理由：（一句话）

注意：
- 本地方案考虑设备内存（\(ramGB) GB）是否够用
- 云端方案必须在用户所在地区可直接访问（无需代理），根据地区避开当地无法访问的服务
- 只推荐兼容 OpenAI /v1/audio/transcriptions 格式的服务
"""
        let llm = makeLLMFromDraft()
        advisorStreamTask = llm.streamChat(
            messages: [LLMMessage(role: "user", content: prompt)],
            onChunk: { [self] chunk in
                guard advisorResult.count < 50_000 else { return }
                advisorResult += String(chunk.prefix(50_000 - advisorResult.count))
            },
            onDone: { [self] in
                advisorStreaming = false
                advisorStreamTask = nil
            }
        )
    }

    private func makeLLMFromDraft() -> LLMProvider {
        let p = draft.selectedProfile
        return OpenAICompatibleProvider(baseURL: p.baseURL, apiKey: p.apiKey, model: p.selectedModel)
    }

    // MARK: - Expandable Section


    // MARK: - Hotkey

    private static let defaultHotkeyKeyCode: UInt16 = UInt16.max
    private static let defaultHotkeyModifiers: [String] = ["control"]

    private var hotkeyPane: some View {
        Form {
            Section(header: Text("全局快捷键"), footer: Text("支持修饰键单击或单独修饰键双击（如双击 ⌃），需包含至少一个修饰键。").font(.caption).foregroundColor(.secondary)) {
                shortcutRow(
                    label: "开启 Murmur",
                    keyCode: $draft.hotkeyKeyCode,
                    modifiers: $draft.hotkeyModifiers,
                    defaultKeyCode: Self.defaultHotkeyKeyCode,
                    defaultModifiers: Self.defaultHotkeyModifiers,
                    requiresModifier: true,
                    allowModifierOnly: true,
                    showDoubleTap: true,
                    helpText: "恢复默认（双击 Control）"
                )
            }

            Section(header: Text("应用内快捷键"), footer: Text("支持修饰键组合或单个裸键，不支持双击。").font(.caption).foregroundColor(.secondary)) {
                ForEach($draft.appShortcuts) { $shortcut in
                    let def = AppShortcut.defaults.first { $0.id == shortcut.id }
                    shortcutRow(
                        label: shortcut.name,
                        keyCode: $shortcut.keyCode,
                        modifiers: $shortcut.modifiers,
                        defaultKeyCode: def?.keyCode ?? shortcut.keyCode,
                        defaultModifiers: def?.modifiers ?? shortcut.modifiers,
                        requiresModifier: false,
                        allowModifierOnly: false,
                        showDoubleTap: false,
                        helpText: "恢复默认"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("快捷键")
    }

    @ViewBuilder
    private func shortcutRow(
        label: String,
        keyCode: Binding<UInt16>,
        modifiers: Binding<[String]>,
        defaultKeyCode: UInt16,
        defaultModifiers: [String],
        requiresModifier: Bool,
        allowModifierOnly: Bool,
        showDoubleTap: Bool,
        helpText: String
    ) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShortcutRecorderView(
                keyCode: keyCode,
                modifiers: modifiers,
                requiresModifier: requiresModifier,
                allowModifierOnly: allowModifierOnly,
                showDoubleTap: showDoubleTap
            )
            .frame(width: 120, height: 26)
            Button {
                keyCode.wrappedValue = defaultKeyCode
                modifiers.wrappedValue = defaultModifiers
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(helpText)
        }
    }

    // MARK: - Output

    private var outputPane: some View {
        Form {
            Section("输出方式") {
                Text("写入剪贴板后模拟 ⌘V 注入光标位置。原剪贴板内容将在 1 秒后恢复。\n需要辅助功能权限（Accessibility）。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("输出")
    }

    // MARK: - Templates

    private var templatesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach($draft.editedBuiltins) { $t in
                    templateRow(template: $t, isBuiltin: true,
                                defaultTemplate: PromptTemplate.builtins.first { $0.id == t.id },
                                onDelete: nil)
                }
                ForEach($draft.customTemplates) { $t in
                    let idx = draft.customTemplates.firstIndex { $0.id == t.id }
                    templateRow(template: $t, isBuiltin: false, defaultTemplate: nil,
                                onDelete: idx.map { i in { draft.customTemplates.remove(at: i) } })
                }
                Button("添加模板") {
                    let t = PromptTemplate(id: UUID().uuidString, name: "", promptInstruction: "")
                    draft.customTemplates.append(t)
                    expandedTemplateIDs.insert(t.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
        }
        .navigationTitle("提示词模板")
    }

    @ViewBuilder
    private func templateRow(
        template: Binding<PromptTemplate>,
        isBuiltin: Bool,
        defaultTemplate: PromptTemplate?,
        onDelete: (() -> Void)?
    ) -> some View {
        let t = template.wrappedValue
        let isExpanded = expandedTemplateIDs.contains(t.id)
        let isModified = isBuiltin && (t.name != defaultTemplate?.name || t.promptInstruction != defaultTemplate?.promptInstruction)

        VStack(spacing: 0) {
            // ── 折叠态 ──
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedTemplateIDs.remove(t.id) }
                    else          { expandedTemplateIDs.insert(t.id) }
                }
            } label: {
                HStack {
                    Text(t.name.isEmpty ? "未命名" : t.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Spacer()
                    if isModified, let def = defaultTemplate {
                        Button {
                            template.wrappedValue.name = def.name
                            template.wrappedValue.promptInstruction = def.promptInstruction
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(MurmurFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("恢复默认")
                    }
                    if let del = onDelete {
                        Button { del() } label: {
                            Image(systemName: "trash")
                                .font(MurmurFont.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(MurmurFont.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── 展开态 ──
            if isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    profileFieldRow(label: "名称", content: {
                        TextField("", text: template.name, prompt: Text("模板名称"))
                            .font(MurmurFont.secondary)
                    })
                    Divider()
                    profileFieldRow(label: "提示词", content: {
                        TextField("", text: Binding(
                            get: { template.wrappedValue.promptInstruction ?? "" },
                            set: { template.wrappedValue.promptInstruction = $0.isEmpty ? nil : $0 }
                        ), prompt: Text("留空表示默认模式"), axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                        .font(MurmurFont.secondary)
                    })
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12 as Double), lineWidth: 1))
    }

    // MARK: - Vocabulary

    private var vocabularyPane: some View {
        VStack(spacing: 0) {
            Text("热词会在提交时自动替换（整词匹配）。例：输入 tmr → 自动展开为 tomorrow。")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top])

            List {
                ForEach($vocabWords) { $entry in
                    HStack {
                        TextField("触发词", text: $entry.trigger).frame(width: 100)
                        Text("→").foregroundColor(.secondary)
                        TextField("展开为", text: $entry.expansion)
                    }
                }
                .onDelete { vocabWords.remove(atOffsets: $0) }
            }
            Divider()
            HStack {
                Spacer()
                Button("添加热词") {
                    vocabWords.append(VocabEntry(trigger: "", expansion: ""))
                }.buttonStyle(.bordered)
            }.padding(.horizontal).padding(.vertical, 8)
        }
        .onChange(of: vocabWords) { words in
            try? VocabularyStore(words: words).save()
        }
        .navigationTitle("热词")
    }

    // MARK: - History

    private var historyPane: some View {
        Form {
            Section("分组方式") {
                Picker("默认分组", selection: $draft.historyGroupMode) {
                    ForEach(HistoryGroupMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Text("打开历史记录窗口时使用此分组方式。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("存储限制") {
                Stepper("最多保留 \(draft.historyMaxEntries) 条", value: $draft.historyMaxEntries, in: 100...5000, step: 100)
                Text("超出上限时自动删除最早的记录。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("历史记录")
    }
}

// MARK: - ASR Advisor Sheet

struct ASRAdvisorSheet: View {
    @Binding var region: String
    @Binding var language: String
    @Binding var result: String
    @Binding var isStreaming: Bool
    let hardwareInfo: String
    let onAdd: (String, String, String) -> Void
    let onAsk: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("语音识别模型建议").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }.buttonStyle(.plain).foregroundColor(.secondary)
            }

            // 硬件信息
            Text(hardwareInfo)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("所在地区").frame(width: 64, alignment: .leading)
                    TextField("", text: $region, prompt: Text("如：中国大陆、北美、欧洲"))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("主要语言").frame(width: 64, alignment: .leading)
                    TextField("", text: $language, prompt: Text("如：中文、英语、中英混合"))
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 按钮行
            HStack(spacing: 10) {
                Button(isStreaming ? "分析中…" : "获取建议") {
                    onAsk()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStreaming)

                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("AI 正在分析…").font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !result.isEmpty && !isStreaming {
                    Button("导出") { exportResult() }
                        .buttonStyle(.bordered)
                }
            }

            if !result.isEmpty {
                Divider()
                ScrollView {
                    Text(result)
                        .font(MurmurFont.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 280)

                Text("AI 建议，仅供参考")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func exportResult() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "语音识别模型建议.txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? result.write(to: url, atomically: true, encoding: .utf8)
        }
    }
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
    var onToggleVisible: () -> Void
    var onSave: () -> Void
    var onCancel: () -> Void
    var onEdit: () -> Void

    /// 同一渲染周期内同时更新 key 和 hasUnsavedInput，避免竞态导致误触发锁定。
    @State private var hasUnsavedInput = false

    private var editableKey: Binding<String> {
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
        let keyPrompt = optional ? "可选，大多数本地语音识别服务无需填写" : "必填，输入 API Key"

        HStack(spacing: 8) {
            Text("Key")
                .font(MurmurFont.secondary)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .leading)

            if locked {
                Text("••••••••（已配置）")
                    .font(MurmurFont.secondary).foregroundColor(.secondary)
                Spacer()
                Button("配置") { onEdit() }
                    .buttonStyle(.bordered).controlSize(.mini)
            } else {
                Group {
                    if keyVisible {
                        TextField("", text: editableKey, prompt: Text(keyPrompt))
                    } else {
                        SecureField("", text: editableKey, prompt: Text(keyPrompt))
                    }
                }
                .font(MurmurFont.secondary)

                if hasContent {
                    Button { onToggleVisible() } label: {
                        Image(systemName: keyVisible ? "eye.slash" : "eye")
                            .font(MurmurFont.caption).foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if isEditing {
                    Button("完成") {
                        hasUnsavedInput = false
                        onSave()
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                    Button("取消") {
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
