import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var phrasedWindowController: PhrasedWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var warmUpTask: Task<Void, Never>?

    private var settings = PhrasedSettings()
    private lazy var historyStore: HistoryStore = {
        let s = HistoryStore()
        s.retentionDays = settings.historyRetentionDays
        return s
    }()
    private lazy var vocabularyStore = VocabularyStore.loadOrDefault()
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel(transcriber: makeASRProvider())
    private lazy var confirmVM = ConfirmViewModel(llm: makeLLMProvider(), processor: processor, historyStore: historyStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        PhrasedSettings.migrateStorageDirectoryIfNeeded()
        settings = PhrasedSettings.loadOrDefault()
        if PhrasedSettings.settingsWereReset {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("app.alert.settings_corrupted.title", comment: "")
                alert.informativeText = NSLocalizedString("app.alert.settings_corrupted.message", comment: "")
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        NSApp.setActivationPolicy(.accessory)

        phrasedWindowController = PhrasedWindowController(inputVM: inputVM, confirmVM: confirmVM)
        phrasedWindowController?.installAppShortcutMonitor()

        inputVM.settings = settings
        inputVM.allTemplates = settings.allTemplates
        inputVM.vocabularyStore = vocabularyStore
        inputVM.onSubmit = { [weak self] text, template in
            guard let self else { return }
            if self.settings.selectedProfile.selectedModel.isEmpty {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("app.alert.llm_not_configured.title", comment: "")
                alert.informativeText = NSLocalizedString("app.alert.llm_not_configured.message", comment: "")
                alert.addButton(withTitle: NSLocalizedString("app.button.go_to_settings", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("app.button.cancel", comment: ""))
                if alert.runModal() == .alertFirstButtonReturn {
                    self.showSettings()
                }
                return
            }
            let context = self.phrasedWindowController?.pendingContext ?? .empty
            self.confirmVM.start(input: text, template: template, context: context)
        }

        statusBarController = StatusBarController(appDelegate: self)

        hotkeyManager = HotkeyManager(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyNSModifiers,
            onActivate: { [weak self] in self?.showWindow() }
        )

        // Pre-warm: kick off a single-token request so the model is loaded before first use
        warmUpTask = makeLLMProvider().streamChat(
            messages: [LLMMessage(role: .user, content: "hi")],
            onChunk: { _ in },
            onDone: {},
            onError: { _ in }
        )
        inputVM.warmUpTranscriber()

        // Request Accessibility permission (needed for selected text capture)
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // 同步开机启动状态（settings 可能被用户手动改过）
        LaunchAtLoginHelper.set(enabled: settings.launchAtLogin)
        // 同步 confirmVM settings（用于提示音）
        confirmVM.settings = settings
    }

    // MARK: - Menu actions (called by StatusBarController menu items)

    @objc func menuOpen(_ sender: Any?) { showWindow() }

    @objc func menuHistory(_ sender: Any?) { showHistory() }

    @objc func menuQuit(_ sender: Any?) { NSApplication.shared.terminate(nil) }

    @objc func menuSettings(_ sender: Any?) { showSettings() }

    // MARK: - Private

    private func makeASRProvider() -> ASRProvider {
        let profile = settings.selectedASRProfile
        switch profile.providerType {
        case .sfspeech: return SFSpeechTranscriber()
        case .api:      return CloudASRTranscriber(baseURL: profile.baseURL, apiKey: profile.apiKey, model: profile.model)
        }
    }

    private func makeLLMProvider() -> LLMProvider {
        let profile = settings.selectedProfile
        return OpenAICompatibleProvider(
            baseURL: profile.baseURL,
            apiKey: profile.apiKey,
            model: profile.selectedModel
        )
    }

    private func showWindow() {
        let context = ContextCapture.capture()
        phrasedWindowController?.show(context: context)
    }

    private func showSettings() {
        if let controller = settingsWindowController {
            controller.updateSettings(
                settings,
                onSave: { [weak self] newSettings in self?.applySettings(newSettings) },
                onOpenHistory: { [weak self] in self?.showHistory() },
                onExportHistory: { [weak self] in
                    guard let self else { return }
                    let entries = (try? self.historyStore.load()) ?? []
                    HistoryExporter.export(entries: entries)
                }
            )
            controller.showWindow(nil)
        } else {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onSave: { [weak self] newSettings in self?.applySettings(newSettings) },
                onOpenHistory: { [weak self] in self?.showHistory() },
                onExportHistory: { [weak self] in
                    guard let self else { return }
                    let entries = (try? self.historyStore.load()) ?? []
                    HistoryExporter.export(entries: entries)
                }
            )
            settingsWindowController?.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applySettings(_ newSettings: PhrasedSettings) {
        settings = newSettings
        try? newSettings.save()
        inputVM.settings = newSettings
        confirmVM.settings = newSettings
        historyStore.retentionDays = newSettings.historyRetentionDays
        hotkeyManager?.update(keyCode: newSettings.hotkeyKeyCode, modifiers: newSettings.hotkeyNSModifiers)
        confirmVM.updateProvider(makeLLMProvider())
        inputVM.updateASRProvider(makeASRProvider())
        phrasedWindowController?.updateTemplates(newSettings.allTemplates)
        LaunchAtLoginHelper.set(enabled: newSettings.launchAtLogin)
    }

    private func showHistory() {
        if historyWindowController == nil || historyWindowController?.window?.isVisible == false {
            historyWindowController = HistoryWindowController(store: historyStore, groupMode: settings.historyGroupMode)
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        warmUpTask?.cancel()
    }
}
