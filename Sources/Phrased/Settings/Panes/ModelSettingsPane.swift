import SwiftUI

extension SettingsView {
    // MARK: - Model

    var modelPane: some View {
        Form {
            Section("settings.model.section") {
                Picker("settings.model.current_profile", selection: $draft.selectedProfileID) {
                    ForEach(draft.localProfiles) { p in
                        Text(p.name.isEmpty ? String(localized: "settings.model.unnamed") : p.name).tag(p.id)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.localProfiles.indices, id: \.self) { idx in
                        llmProfileRow(index: idx)
                    }

                    // 扫描结果：运行中的服务（可添加）
                    if !llmScanResults.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("settings.model.available_models")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                if llmScanResults.count > 1 {
                                    Button("settings.model.add_all") {
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
                                        Text("settings.model.added").font(.caption).foregroundColor(.secondary)
                                    } else {
                                        Button("settings.model.add") {
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
                                Text(String(format: String(localized: "settings.model.more_hidden_format"), String(limited.hiddenCount)))
                                    .font(.caption).foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.top, 4)
                    }

                    // 已安装但未运行
                    if !llmInstalledNotRunning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("settings.model.installed_not_running")
                                .font(.caption).foregroundColor(.secondary)
                            ForEach(llmInstalledNotRunning, id: \.self) { name in
                                Text("• \(name)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.top, llmScanResults.isEmpty ? 4 : 0)
                    }

                    HStack(spacing: 8) {
                        Button("settings.model.scan_local") {
                            scanLocalLLMServices()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(llmScanning)
                        .accessibilityLabel(
                            llmScanning
                            ? NSLocalizedString("accessibility.scanning_local_models", comment: "")
                            : NSLocalizedString("settings.model.scan_local", comment: "")
                        )
                        .overlay {
                            if llmScanning {
                                ProgressView().scaleEffect(0.5).offset(x: -4)
                            }
                        }

                        Button("settings.model.add_cloud") {
                            let p = LLMProfile(name: "", baseURL: "https://")
                            draft.localProfiles.append(p)
                            expandedLLMProfileIDs.insert(p.id)
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        Menu("settings.model.presets") {
                            ForEach(LLMProfile.cloudPresets, id: \.name) { preset in
                                Button(preset.name) {
                                    let p = LLMProfile(name: preset.name, baseURL: preset.baseURL)
                                    draft.localProfiles.append(p)
                                    expandedLLMProfileIDs.insert(p.id)
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .buttonStyle(.bordered).controlSize(.small)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .alert("settings.model.alert.delete_active.title", isPresented: Binding(
                        get: { deleteActiveProfileIndex != nil },
                        set: { if !$0 { deleteActiveProfileIndex = nil } }
                    )) {
                        Button("settings.model.alert.delete_active.confirm", role: .destructive) {
                            if let idx = deleteActiveProfileIndex, idx < draft.localProfiles.count {
                                _ = expandedLLMProfileIDs.remove(draft.localProfiles[idx].id)
                                draft.localProfiles.remove(at: idx)
                                if let first = draft.localProfiles.first {
                                    draft.selectedProfileID = first.id
                                }
                            }
                            deleteActiveProfileIndex = nil
                        }
                        Button("app.button.cancel", role: .cancel) { deleteActiveProfileIndex = nil }
                    } message: {
                        Text("settings.model.alert.delete_active.message")
                    }
                    .alert("settings.model.alert.none_found.title", isPresented: Binding(
                        get: { llmScanDone && llmScanResults.isEmpty && llmInstalledNotRunning.isEmpty && !llmScanning },
                        set: { if !$0 { llmScanDone = false } }
                    )) {
                        Button("app.button.cancel", role: .cancel) { llmScanDone = false }
                        Button("settings.button.manual_add") {
                            llmScanDone = false
                            let p = LLMProfile(name: "", baseURL: "http://localhost:")
                            draft.localProfiles.append(p)
                            expandedLLMProfileIDs.insert(p.id)
                        }
                    } message: {
                        Text("settings.model.alert.none_found.message")
                    }
                }
            } header: {
                Text("settings.model.advanced")
            } footer: {
                Text("settings.model.description")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("settings.model.navigation_title")
    }

    @ViewBuilder
    func llmProfileRow(index: Int) -> some View {
        if index < draft.localProfiles.count {
            let profile = draft.localProfiles[index]
            let isExpanded = expandedLLMProfileIDs.contains(profile.id)
            let llmCategory = (profile.baseURL.hasPrefix("http://localhost") || profile.baseURL.hasPrefix("http://127.")) ? String(localized: "settings.model.category.local") : String(localized: "settings.model.category.cloud")

            ExpandableCard(
                isExpanded: isExpanded,
                onToggle: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if isExpanded {
                            _ = expandedLLMProfileIDs.remove(profile.id)
                            editingKeyLLMProfileID = nil
                        } else {
                            expandedLLMProfileIDs.insert(profile.id)
                        }
                    }
                },
                onDelete: {
                    let isActive = profile.id == draft.selectedProfileID
                    if isActive && draft.localProfiles.count > 1 {
                        deleteActiveProfileIndex = index
                    } else {
                        _ = expandedLLMProfileIDs.remove(profile.id)
                        draft.localProfiles.remove(at: index)
                        draft.selectedProfileID = draft.localProfiles.first?.id ?? UUID()
                    }
                }
            ) {
                Text(profile.name.isEmpty ? String(localized: "settings.model.unnamed") : profile.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(llmCategory)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } detail: {
                VStack(alignment: .leading, spacing: 0) {
                    let isLocal = draft.localProfiles[index].baseURL.hasPrefix("http://localhost") ||
                        draft.localProfiles[index].baseURL.hasPrefix("http://127.")
                    profileField("settings.model.field.name", text: $draft.localProfiles[index].name, prompt: "settings.model.prompt.model_label")
                    Divider()
                    profileField(
                        "settings.model.field.address",
                        text: $draft.localProfiles[index].baseURL,
                        prompt: LocalizedStringKey(isLocal ? "http://localhost:11434" : "https://api.openai.com")
                    )
                    Divider()
                    profileField(
                        "settings.model.field.model",
                        text: $draft.localProfiles[index].selectedModel,
                        prompt: LocalizedStringKey(isLocal ? "qwen2.5:7b" : "gpt-4o-mini")
                    )
                    Divider()
                    llmKeyRow(index: index, profile: profile)
                    Divider()
                    llmTestRow(index: index, profile: profile)
                }
            }
            .id(profile.id)
            .accessibilityAction(
                named: String(
                    format: NSLocalizedString("accessibility.delete_profile_format", comment: ""),
                    profile.name
                )
            ) {
                let isActive = profile.id == draft.selectedProfileID
                if isActive && draft.localProfiles.count > 1 {
                    deleteActiveProfileIndex = index
                } else {
                    _ = expandedLLMProfileIDs.remove(profile.id)
                    draft.localProfiles.remove(at: index)
                    draft.selectedProfileID = draft.localProfiles.first?.id ?? UUID()
                }
            }
        }
    }

    @ViewBuilder
    func llmKeyRow(index: Int, profile: LLMProfile) -> some View {
        let isLocal = draft.localProfiles[index].baseURL.hasPrefix("http://localhost") ||
                      draft.localProfiles[index].baseURL.hasPrefix("http://127.")
        profileKeyRow(
            key: $draft.localProfiles[index].apiKey,
            isEditing: editingKeyLLMProfileID == profile.id,
            keyVisible: llmKeyVisible,
            optional: isLocal,
            configureAccessibilityLabel: String(
                format: NSLocalizedString("accessibility.configure_api_key_format", comment: ""),
                profile.name
            ),
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

    @ViewBuilder
    func llmTestRow(index: Int, profile: LLMProfile) -> some View {
        let testing = llmTestingProfileID == profile.id
        HStack {
            Spacer()
            if testing {
                ProgressView().scaleEffect(0.6)
            } else if let result = llmTestResults[profile.id] {
                if result.ok {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(result.message).font(.caption).foregroundColor(.secondary)
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text(result.message).font(.caption).foregroundColor(.red).lineLimit(1)
                }
            }
            Button("settings.model.test_connection") {
                testLLMConnection(profile: draft.localProfiles[index])
            }
            .buttonStyle(.bordered).controlSize(.mini)
            .disabled(testing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func testLLMConnection(profile: LLMProfile) {
        let id = profile.id
        llmTestingProfileID = id
        llmTestResults.removeValue(forKey: id)

        Task {
            let result = await performLLMTest(profile: profile)
            await MainActor.run {
                llmTestingProfileID = nil
                llmTestResults[id] = result
            }
        }
    }

    private func performLLMTest(profile: LLMProfile) async -> (ok: Bool, message: String) {
        let base = profile.baseURL.hasSuffix("/") ? String(profile.baseURL.dropLast()) : profile.baseURL
        guard !base.isEmpty, let url = URL(string: base + OpenAICompatibleProvider.chatCompletionsPath(for: base)) else {
            return (false, String(localized: "settings.model.test.error.invalid_url"))
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !profile.apiKey.isEmpty {
            request.setValue("Bearer \(profile.apiKey)", forHTTPHeaderField: "Authorization")
        }
        let model = profile.selectedModel.isEmpty ? "gpt-4o-mini" : profile.selectedModel
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "hi"]],
            "max_tokens": 1
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let start = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            guard let http = response as? HTTPURLResponse else {
                return (false, String(localized: "settings.model.test.error.invalid_response"))
            }
            if http.statusCode == 200 {
                return (true, "\(elapsed) ms")
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = json["error"] as? [String: Any],
               let msg = err["message"] as? String {
                return (false, "HTTP \(http.statusCode): \(msg)")
            }
            return (false, "HTTP \(http.statusCode)")
        } catch let e as URLError {
            switch e.code {
            case .timedOut:              return (false, String(localized: "settings.model.test.error.timeout"))
            case .cannotConnectToHost,
                 .networkConnectionLost: return (false, String(localized: "settings.model.test.error.cannot_connect"))
            case .notConnectedToInternet: return (false, String(localized: "settings.model.test.error.no_network"))
            default:                     return (false, e.localizedDescription)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    var llmScanResultsLimited: (visible: [ServiceScanResult], hiddenCount: Int) {
        let maxPerHost = 5
        var seen: [String: Int] = [:]
        var visible: [ServiceScanResult] = []
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

    private var knownLLMPackages: [(binary: String?, appName: String?, brew: String?, name: String, port: Int)] {
        [
            ("ollama", nil,         "ollama",    "Ollama",    11434),
            (nil,      "LM Studio", nil,         "LM Studio", 1234),
            (nil,      "Jan",       nil,         "Jan",       1337),
            (nil,      nil,         "llama.cpp", "llama.cpp", 8080),
        ]
    }

    private var knownLLMPorts: [(port: Int, name: String)] {
        [
            (11434, "Ollama"),
            (1234,  "LM Studio"),
            (1337,  "Jan"),
            (8080,  "llama.cpp"),
            (8000,  String(localized: "settings.audio.local_service_name")),
        ]
    }

    func scanLocalLLMServices() {
        llmScanning = true
        llmScanResults = []
        llmInstalledNotRunning = []
        llmScanDone = false

        Task {
            let portNames = Dictionary(uniqueKeysWithValues: knownLLMPorts.map { ($0.port, $0.name) })
            let scan = await LocalServiceScanner.scan(
                portProbes: knownLLMPorts.map { entry in
                    LocalServiceProbe(port: entry.port) { baseURL in
                        await LocalServiceScanner.probeOpenAIModelList(at: baseURL)
                    }
                },
                installedServiceChecks: knownLLMPackages.map { pkg in
                    var checks: [InstallCheck] = []
                    if let binary = pkg.binary {
                        checks.append(.package(InstalledPackage(name: binary, shellCommand: ["which", binary])))
                    }
                    if let appName = pkg.appName {
                        checks.append(.custom {
                            LocalServiceScanner.appInstalled(appName)
                        })
                    }
                    if let brew = pkg.brew {
                        checks.append(.package(InstalledPackage(name: brew, shellCommand: ["brew", "list", brew])))
                    }

                    return InstalledServiceCheck(name: pkg.name, port: pkg.port, checks: checks) { baseURL, models in
                        if models.isEmpty {
                            return [ScannedService(name: pkg.name, baseURL: baseURL, model: "")]
                        }
                        return models.map { model in
                            ScannedService(name: model, baseURL: baseURL, model: model)
                        }
                    }
                },
                mapUnknownRunning: { baseURL, port, models in
                    let name = portNames[port] ?? String(
                        format: String(localized: "settings.audio.local_service_with_port_format"),
                        String(port)
                    )
                    if models.isEmpty {
                        return [ScannedService(name: name, baseURL: baseURL, model: "")]
                    }
                    return models.map { model in
                        ScannedService(name: model, baseURL: baseURL, model: model)
                    }
                }
            )

            await MainActor.run {
                self.llmScanResults = scan.services.map {
                    ServiceScanResult(name: $0.name, baseURL: $0.baseURL, model: $0.model)
                }.filter { r in
                    !self.draft.localProfiles.contains(where: { $0.baseURL == r.baseURL && $0.selectedModel == r.model })
                }
                self.llmInstalledNotRunning = scan.notRunning
                self.llmScanning = false
                self.llmScanDone = true
            }
        }
    }
}
