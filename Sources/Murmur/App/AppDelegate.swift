import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var murmurWindowController: MurmurWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?

    private var settings = MurmurSettings.loadOrDefault()
    private lazy var historyStore: HistoryStore = {
        let s = HistoryStore()
        s.maxEntries = settings.historyMaxEntries
        return s
    }()
    private lazy var vocabularyStore = VocabularyStore.loadOrDefault()
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel(transcriber: makeASRProvider())
    private lazy var confirmVM = ConfirmViewModel(llm: makeLLMProvider(), processor: processor, historyStore: historyStore)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        murmurWindowController = MurmurWindowController(inputVM: inputVM, confirmVM: confirmVM)

        inputVM.settings = settings
        inputVM.allTemplates = settings.allTemplates
        inputVM.vocabularyStore = vocabularyStore
        inputVM.onSubmit = { [weak self] text, template in
            guard let self else { return }
            let context = self.murmurWindowController?.pendingContext ?? .empty
            self.confirmVM.start(input: text, template: template, context: context)
        }

        statusBarController = StatusBarController(appDelegate: self)

        hotkeyManager = HotkeyManager(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyNSModifiers,
            onActivate: { [weak self] in self?.showWindow() }
        )

        // Pre-warm: kick off a single-token request so the model is loaded before first use
        makeLLMProvider().streamChat(
            messages: [LLMMessage(role: "user", content: "hi")],
            onChunk: { _ in }, onDone: {}
        )
        inputVM.warmUpTranscriber()

        // Request Accessibility permission (needed for selected text capture)
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Menu actions (called by StatusBarController menu items)

    @objc func menuOpen(_ sender: Any?) { showWindow() }

    @objc func menuHistory(_ sender: Any?) { showHistory() }

    @objc func menuSettings(_ sender: Any?) { showSettings() }

    // MARK: - Private

    private func makeASRProvider() -> ASRProvider {
        let profile = settings.selectedASRProfile
        switch profile.providerType {
        case "sfspeech": return SFSpeechTranscriber()
        default:         return CloudASRTranscriber(baseURL: profile.baseURL, apiKey: profile.apiKey, model: profile.model)
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
        murmurWindowController?.show(context: context)
    }

    private func showSettings() {
        settingsWindowController = SettingsWindowController(
            settings: settings,
            onSave: { [weak self] newSettings in
                guard let self else { return }
                self.settings = newSettings
                try? newSettings.save()
                self.inputVM.settings = newSettings
                self.historyStore.maxEntries = newSettings.historyMaxEntries
                self.hotkeyManager?.update(
                    keyCode: newSettings.hotkeyKeyCode,
                    modifiers: newSettings.hotkeyNSModifiers
                )
                self.confirmVM.updateProvider(self.makeLLMProvider())
                self.inputVM.updateASRProvider(self.makeASRProvider())
                self.murmurWindowController?.updateTemplates(newSettings.allTemplates)
            }
        )
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHistory() {
        if historyWindowController == nil || historyWindowController?.window?.isVisible == false {
            historyWindowController = HistoryWindowController(store: historyStore, groupMode: settings.historyGroupMode)
        }
        NSApp.activate(ignoringOtherApps: true)
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
