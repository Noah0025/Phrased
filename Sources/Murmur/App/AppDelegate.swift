import AppKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?
    private var inputWindowController: InputWindowController?
    private var confirmWindowController: ConfirmWindowController?

    private lazy var ollama = OllamaClient(model: "qwen2.5:7b")
    private lazy var processor = IntentProcessor()
    private lazy var inputVM = InputViewModel()
    private lazy var confirmVM = ConfirmViewModel(ollama: ollama, processor: processor)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        inputWindowController = InputWindowController(vm: inputVM)
        confirmWindowController = ConfirmWindowController(vm: confirmVM)

        inputVM.onSubmit = { [weak self] text in
            self?.inputWindowController?.window?.orderOut(nil)
            self?.confirmWindowController?.present(input: text)
        }

        statusBarController = StatusBarController { [weak self] in
            self?.showInputWindow()
        }

        hotkeyManager = HotkeyManager { [weak self] in
            self?.showInputWindow()
        }

        // Pre-warm Ollama
        Task {
            _ = try? await URLSession.shared.data(for: self.ollama.buildRequest(
                messages: [OllamaMessage(role: "user", content: "hi")]
            ))
        }
    }

    private func showInputWindow() {
        inputWindowController?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {}
}
