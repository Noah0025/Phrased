import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var murmurWindowController: MurmurWindowController?

    private lazy var llm: LLMProvider = OllamaLLMProvider(model: "qwen2.5:7b")
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel()
    private lazy var confirmVM = ConfirmViewModel(llm: llm, processor: processor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        murmurWindowController = MurmurWindowController(inputVM: inputVM, confirmVM: confirmVM)

        inputVM.onSubmit = { [weak self] text, style in
            guard let self else { return }
            self.confirmVM.start(input: text, style: style)
        }

        statusBarController = StatusBarController { [weak self] in
            self?.showWindow()
        }

        hotkeyManager = HotkeyManager { [weak self] in
            self?.showWindow()
        }

        // Pre-warm: fire a single-token request so the model is loaded before first use
        Task {
            llm.streamChat(messages: [LLMMessage(role: "user", content: "hi")],
                           onChunk: { _ in }, onDone: {})
        }
        inputVM.warmUpTranscriber()
    }

    private func showWindow() {
        murmurWindowController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
