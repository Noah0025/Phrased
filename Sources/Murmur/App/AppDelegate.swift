import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var murmurWindowController: MurmurWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var historyWindowController: HistoryWindowController?

    private var settings = MurmurSettings.loadOrDefault()
    private lazy var historyStore = HistoryStore()
    private lazy var vocabularyStore = VocabularyStore.loadOrDefault()
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel()
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

        statusBarController = StatusBarController(
            onOpen:     { [weak self] in self?.showWindow() },
            onSettings: { [weak self] in self?.showSettings() },
            onHistory:  { [weak self] in self?.showHistory() }
        )

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

    private func makeLLMProvider() -> LLMProvider {
        switch settings.llmProviderID {
        case "openai":
            return OpenAICompatibleProvider(
                baseURL: settings.openAIBaseURL,
                apiKey: settings.openAIAPIKey,
                model: settings.openAIModel
            )
        default:
            return OllamaLLMProvider(model: settings.ollamaModel)
        }
    }

    private func showWindow() {
        let context = ContextCapture.capture()  // must be called before NSApp.activate
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
                self.hotkeyManager?.update(
                    keyCode: newSettings.hotkeyKeyCode,
                    modifiers: newSettings.hotkeyNSModifiers
                )
                self.confirmVM.updateProvider(self.makeLLMProvider())
                self.murmurWindowController?.updateTemplates(newSettings.allTemplates)
            }
        )
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showHistory() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(store: historyStore)
        }
        historyWindowController?.showWindow(nil)
        historyWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
