import SwiftUI
import AppKit

extension SettingsView {
    // MARK: - Audio

    var audioPane: some View {
        Form {
            Section {
                Picker("settings.audio.input_source", selection: $draft.audioSource) {
                    Text("settings.audio.input.system_audio").tag("systemAudio")
                    Text("settings.audio.input.microphone").tag("microphone")
                }
            } header: {
                Text("settings.audio.default_input")
            } footer: {
                Text(draft.isSystemAudio ? "settings.audio.permission.screen_recording" : "settings.audio.permission.microphone")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("settings.audio.asr_model") {
                Picker("settings.model.current_profile", selection: $draft.selectedASRProfileID) {
                    ForEach(draft.asrProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.asrProfiles.indices, id: \.self) { idx in
                        asrProfileRow(index: idx)
                    }

                    if !asrScanResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("settings.audio.available_services")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                if asrScanResults.count > 1 {
                                    Button("settings.model.add_all") {
                                        for r in asrScanResults where !draft.asrProfiles.contains(where: { $0.baseURL == r.baseURL }) {
                                            draft.asrProfiles.append(ASRProfile(name: r.name, providerType: .api, baseURL: r.baseURL, model: r.model))
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
                                        Text("settings.model.added").font(.caption).foregroundColor(.secondary)
                                    } else {
                                        Button("settings.model.add") {
                                            draft.asrProfiles.append(ASRProfile(name: result.name, providerType: .api, baseURL: result.baseURL, model: result.model))
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

                    if !asrInstalledNotRunning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.scan.installed_not_running")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(asrInstalledNotRunning, id: \.self) { name in
                                Text("• \(name)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, asrScanResults.isEmpty ? 4 : 0)
                    }

                    HStack(spacing: 8) {
                        Button("settings.audio.scan_local") {
                            scanLocalASRServices()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(asrScanning)
                        .accessibilityLabel(
                            asrScanning
                            ? NSLocalizedString("accessibility.scanning_local_services", comment: "")
                            : NSLocalizedString("settings.audio.scan_local", comment: "")
                        )
                        .overlay {
                            if asrScanning {
                                ProgressView().scaleEffect(0.5).offset(x: -4)
                            }
                        }

                        Button("settings.audio.add_cloud") {
                            let newProfile = ASRProfile(name: "", providerType: .api,
                                                        baseURL: "https://")
                            draft.asrProfiles.append(newProfile)
                            expandedASRProfileIDs.insert(newProfile.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button("settings.audio.recommendation") {
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
                                        name: name, providerType: .api,
                                        baseURL: baseURL, model: model
                                    ))
                                }
                            },
                            onAsk: { askASRAdvisor() }
                        )
                    }
                    .padding(.top, 4)
                    .alert("settings.audio.alert.none_found.title", isPresented: Binding(
                        get: { asrScanDone && asrScanResults.isEmpty && asrInstalledNotRunning.isEmpty && !asrScanning },
                        set: { if !$0 { asrScanDone = false } }
                    )) {
                        Button("app.button.cancel", role: .cancel) { asrScanDone = false }
                        Button("settings.button.manual_add") {
                            asrScanDone = false
                            let newProfile = ASRProfile(name: "", providerType: .api,
                                                        baseURL: "http://localhost:")
                            draft.asrProfiles.append(newProfile)
                            expandedASRProfileIDs.insert(newProfile.id)
                        }
                    }
                }
            } header: {
                Text("settings.model.advanced")
            } footer: {
                Text("settings.audio.description")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.audio.navigation_title")
    }

    func asrCategory(_ profile: ASRProfile) -> String {
        if profile.providerType == .sfspeech { return String(localized: "settings.audio.category.macos_builtin") }
        let isLocal = profile.baseURL.hasPrefix("http://localhost") || profile.baseURL.hasPrefix("http://127.")
        return isLocal ? String(localized: "settings.model.category.local") : String(localized: "settings.model.category.cloud")
    }

    @ViewBuilder
    func asrProfileRow(index: Int) -> some View {
        if index < draft.asrProfiles.count {
            let profile = draft.asrProfiles[index]
            let isExpanded = expandedASRProfileIDs.contains(profile.id)
            let isSFSpeech = profile.id == ASRProfile.builtinSFSpeech.id

            ExpandableCard(
                isExpanded: isExpanded,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            _ = expandedASRProfileIDs.remove(profile.id)
                            editingKeyASRProfileID = nil
                        } else {
                            expandedASRProfileIDs.insert(profile.id)
                        }
                    }
                },
                onDelete: nil
            ) {
                Text(profile.name.isEmpty ? String(localized: "settings.model.unnamed") : profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(asrCategory(profile))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    if isSFSpeech {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("settings.audio.builtin.description")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("settings.audio.builtin.apple_silicon")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("settings.audio.builtin.intel")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                    } else {
                        let isLocal = asrCategory(draft.asrProfiles[index]) == String(localized: "settings.model.category.local")
                        profileField("settings.field.name", text: $draft.asrProfiles[index].name, prompt: "settings.placeholder.model_label")
                        Divider()
                        profileField(
                            "settings.field.address",
                            text: $draft.asrProfiles[index].baseURL,
                            prompt: LocalizedStringKey(isLocal ? "http://localhost:8000" : "https://api.example.com/v1")
                        )
                        Divider()
                        profileField(
                            "settings.audio.field.asr_model",
                            text: $draft.asrProfiles[index].model,
                            prompt: LocalizedStringKey(isLocal ? "whisper-1" : "whisper-large-v3")
                        )
                        Divider()
                        asrKeyRow(index: index, profile: profile, optional: isLocal)
                        Divider()
                        HStack {
                            Button("settings.button.delete") {
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
                            .accessibilityLabel(String(
                                format: NSLocalizedString("accessibility.delete_profile_format", comment: ""),
                                profile.name
                            ))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                }
            }
            .id(profile.id)
        }
    }

    @ViewBuilder
    func asrKeyRow(index: Int, profile: ASRProfile, optional: Bool = false) -> some View {
        profileKeyRow(
            key: $draft.asrProfiles[index].apiKey,
            isEditing: editingKeyASRProfileID == profile.id,
            keyVisible: asrKeyVisible,
            optional: optional,
            configureAccessibilityLabel: String(
                format: NSLocalizedString("accessibility.configure_api_key_format", comment: ""),
                profile.name
            ),
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

    private var knownPackages: [(pip: String?, brew: String?, name: String, port: Int, model: String)] {
        [
            ("faster-whisper-server", nil,          "faster-whisper-server", 8000, "Systran/faster-whisper-small"),
            (nil,                     "whisper-cpp", "whisper.cpp",           8080, "base"),
            ("openedai-speech",       nil,           "openedai-speech",       8000, "tts-1"),
            ("whisperx",              nil,           "whisperX",              8001, "large-v3"),
        ]
    }

    private var probePorts: [Int] { [8000, 8001, 8080, 8765, 9000, 5000] }

    func scanLocalASRServices() {
        asrScanning = true
        asrScanResults = []
        asrInstalledNotRunning = []
        asrScanDone = false

        Task {
            let scan = await LocalServiceScanner.scan(
                portProbes: probePorts.map { port in
                    LocalServiceProbe(port: port) { baseURL in
                        await LocalServiceScanner.probeOpenAICompatibleModelEndpoint(at: baseURL)
                    }
                },
                installedServiceChecks: knownPackages.map { pkg in
                    var checks: [InstallCheck] = []
                    if let pip = pkg.pip {
                        checks.append(.package(InstalledPackage(name: pip, shellCommand: ["pip3", "show", pip])))
                    }
                    if let brew = pkg.brew {
                        checks.append(.package(InstalledPackage(name: brew, shellCommand: ["brew", "list", brew])))
                    }

                    return InstalledServiceCheck(name: pkg.name, port: pkg.port, checks: checks) { baseURL, _ in
                        [ScannedService(name: pkg.name, baseURL: baseURL, model: pkg.model)]
                    }
                },
                mapUnknownRunning: { baseURL, port, _ in
                    [ScannedService(
                        name: String(
                            format: String(localized: "settings.audio.local_service_with_port_format"),
                            String(port)
                        ),
                        baseURL: baseURL,
                        model: ""
                    )]
                }
            )

            await MainActor.run {
                self.asrScanResults = scan.services.map {
                    ServiceScanResult(name: $0.name, baseURL: $0.baseURL, model: $0.model)
                }.filter { r in
                    !self.draft.asrProfiles.contains(where: { $0.baseURL == r.baseURL })
                }
                self.asrInstalledNotRunning = scan.notRunning
                self.asrScanning = false
                self.asrScanDone = true
            }
        }
    }

    func hardwareInfo() -> String {
        var memSize: UInt64 = 0
        var memLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memLen, nil, 0)
        let ramGB = memSize / (1024 * 1024 * 1024)

        var cpuBuf = [CChar](repeating: 0, count: 256)
        var cpuLen = cpuBuf.count
        sysctlbyname("machdep.cpu.brand_string", &cpuBuf, &cpuLen, nil, 0)
        let cpu = String(cString: cpuBuf)

        var archBuf = [CChar](repeating: 0, count: 64)
        var archLen = archBuf.count
        sysctlbyname("hw.machine", &archBuf, &archLen, nil, 0)
        let arch = String(cString: archBuf)
        let chipDesc = cpu.isEmpty ? (arch.contains("arm") ? String(localized: "settings.hardware.apple_silicon") : String(localized: "settings.hardware.unknown")) : cpu
        return String(format: String(localized: "settings.hardware.format"), chipDesc, String(ramGB))
    }

    func askASRAdvisor() {
        advisorStreamTask?.cancel()
        advisorStreaming = true
        advisorResult = ""
        let hw = hardwareInfo()
        var memSize: UInt64 = 0; var memLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memLen, nil, 0)
        let ramGB = memSize / (1024 * 1024 * 1024)
        let region = advisorRegion.isEmpty ? String(localized: "settings.asr_advisor.unspecified") : advisorRegion
        let lang = advisorLanguage.isEmpty ? String(localized: "settings.asr_advisor.unspecified") : advisorLanguage
        let prompt = String(format: NSLocalizedString("settings.asr_advisor.prompt_format", comment: ""),
                            hw, region, lang, ramGB)
        let llm = makeLLMFromDraft()
        advisorStreamTask = llm.streamChat(
            messages: [LLMMessage(role: .user, content: prompt)],
            onChunk: { [self] chunk in
                guard advisorResult.count < 50_000 else { return }
                advisorResult += String(chunk.prefix(50_000 - advisorResult.count))
            },
            onDone: { [self] in
                advisorStreaming = false
                advisorStreamTask = nil
            },
            onError: { [self] _ in
                advisorStreaming = false
                advisorStreamTask = nil
            }
        )
    }

    func makeLLMFromDraft() -> LLMProvider {
        let p = draft.selectedProfile
        return OpenAICompatibleProvider(baseURL: p.baseURL, apiKey: p.apiKey, model: p.selectedModel)
    }
}

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
                Text("settings.asr_advisor.title").font(.headline)
                Spacer()
                Button("settings.asr_advisor.close") { dismiss() }.buttonStyle(.plain).foregroundColor(.secondary)
            }

            Text(hardwareInfo)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("settings.asr_advisor.region").frame(width: 64, alignment: .leading)
                    TextField("", text: $region, prompt: Text("settings.asr_advisor.region_placeholder"))
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("settings.asr_advisor.language").frame(width: 64, alignment: .leading)
                    TextField("", text: $language, prompt: Text("settings.asr_advisor.language_placeholder"))
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 10) {
                Button(isStreaming ? String(localized: "settings.asr_advisor.analyzing") : String(localized: "settings.asr_advisor.get_recommendations")) {
                    onAsk()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStreaming)

                if isStreaming {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("settings.asr_advisor.ai_analyzing").font(.caption).foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !result.isEmpty && !isStreaming {
                    Button("settings.asr_advisor.export") { exportResult() }
                        .buttonStyle(.bordered)
                }
            }

            if !result.isEmpty {
                Divider()
                ScrollView {
                    Text(result)
                        .font(PhrasedFont.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 280)

                Text("settings.asr_advisor.disclaimer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    func exportResult() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "settings.asr_advisor.export_filename")
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? result.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
