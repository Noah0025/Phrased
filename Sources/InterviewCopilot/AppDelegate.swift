import AppKit
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var floatingPanel: FloatingPanel?
    var audioCapture: AudioCapture?
    var speechTranscriber: SpeechTranscriber?
    var ollamaClient: OllamaClient?
    var subtitleFeature: SubtitleFeature?
    var answerFeature: AnswerFeature?
    var hotkeyManager: HotkeyManager?

    private var isListening = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        setupComponents()
        showPanel()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Murmur")
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    private func setupComponents() {
        ollamaClient = OllamaClient()
        ollamaClient?.warmup() // Pre-load model into GPU memory
        floatingPanel = FloatingPanel()
        speechTranscriber = SpeechTranscriber()
        audioCapture = AudioCapture()
        subtitleFeature = SubtitleFeature(
            transcriber: speechTranscriber!,
            ollama: ollamaClient!,
            panel: floatingPanel!
        )
        answerFeature = AnswerFeature(
            transcriber: speechTranscriber!,
            ollama: ollamaClient!,
            panel: floatingPanel!
        )
        hotkeyManager = HotkeyManager(
            onToggleListen: { [weak self] in self?.toggleListening() },
            onSuggestAnswer: { [weak self] in self?.answerFeature?.trigger() }
        )

        // ▶/⏸ Start/Stop: controls listening + segment
        floatingPanel?.onStartStop = { [weak self] start in
            guard let self else { return }
            if start {
                if !self.isListening { self.startListening() }
                self.subtitleFeature?.startSegment()
            } else {
                self.subtitleFeature?.stopSegment()
                // Keep audio running, just pause segmentation
            }
        }

        // ✂ Cut: finalize current segment, immediately start new one
        floatingPanel?.onCut = { [weak self] in
            guard let self else { return }
            self.subtitleFeature?.stopSegment()
            self.subtitleFeature?.startSegment()
        }

        // Block click → copy to clipboard
        floatingPanel?.onBlockClicked = { en, zh, metadata in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("\(en)\n\(zh)", forType: .string)
            print("[Block] Copied to clipboard")
        }

        // Test mode
        if CommandLine.arguments.contains("--test"), let panel = floatingPanel {
            let testView = panel.addTestInput()
            let transcriber = speechTranscriber!
            testView.onPartial = { text in
                transcriber.onPartial?(text)
            }
            testView.onFinal = { text in
                transcriber.onFinal?(text)
            }
            print("[TestMode] Active — type text or press ▶ Auto")
        }
    }

    private func showPanel() {
        floatingPanel?.show()
    }

    @objc private func togglePanel() {
        if floatingPanel?.isVisible == true {
            floatingPanel?.orderOut(nil)
        } else {
            floatingPanel?.show()
        }
    }

    private func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        guard !isListening else { return }
        isListening = true
        speechTranscriber?.startSession()
        audioCapture?.start { [weak self] buffer in
            self?.speechTranscriber?.appendBuffer(buffer)
        }
    }

    private func stopListening() {
        guard isListening else { return }
        isListening = false
        audioCapture?.stop()
        speechTranscriber?.stopSession()
    }

    func applicationWillTerminate(_ notification: Notification) {
        audioCapture?.stop()
        speechTranscriber?.stopSession()
    }
}
