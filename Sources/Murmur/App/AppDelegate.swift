import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var murmurWindowController: MurmurWindowController?
    private var settingsWindowController: SettingsWindowController?

    private var settings = MurmurSettings.loadOrDefault()
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel()
    private lazy var confirmVM = ConfirmViewModel(llm: makeLLMProvider(), processor: processor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        murmurWindowController = MurmurWindowController(inputVM: inputVM, confirmVM: confirmVM)

        inputVM.settings = settings
        inputVM.onSubmit = { [weak self] text, style in
            guard let self else { return }
            self.confirmVM.start(input: text, style: style)
        }

        statusBarController = StatusBarController(
            onOpen:     { [weak self] in self?.showWindow() },
            onSettings: { [weak self] in self?.showSettings() },
            onHistory:  { } // wired in Phase 6
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

    private func showWindow() { murmurWindowController?.show() }

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
                // TODO: Phase 3 — self.murmurWindowController?.updateTemplates(newSettings.allTemplates)
            }
        )
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
