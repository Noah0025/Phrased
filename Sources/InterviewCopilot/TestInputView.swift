import AppKit

/// Shown at the bottom of FloatingPanel when launched with --test
class TestInputView: NSView {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?

    private let textField = NSTextField()
    private let partialBtn = NSButton(title: "→ Partial", target: nil, action: nil)
    private let finalBtn = NSButton(title: "✓ Final", target: nil, action: nil)
    private let autoBtn = NSButton(title: "▶ Auto", target: nil, action: nil)

    // Canned sentences for auto-play test
    private let testSentences = [
        "stocks are finally entering correction territory",
        "which if you have a 401k like myself that's not exactly welcome news",
        "of course if your own oil is actually quite welcome news",
        "that you've seen gas prices go up in oil prices climb ever higher",
        "now of course one of the key things that's been spoken about",
        "is potentially a ground invasion of Iran",
    ]
    private var autoTimer: Timer?
    private var autoIndex = 0
    private var autoWordIndex = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer?.cornerRadius = 8

        textField.placeholderString = "Type partial text here..."
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.translatesAutoresizingMaskIntoConstraints = false

        for btn in [partialBtn, finalBtn, autoBtn] {
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.translatesAutoresizingMaskIntoConstraints = false
        }
        partialBtn.target = self; partialBtn.action = #selector(sendPartial)
        finalBtn.target = self;   finalBtn.action = #selector(sendFinal)
        autoBtn.target = self;    autoBtn.action = #selector(toggleAuto)

        let btnStack = NSStackView(views: [partialBtn, finalBtn, autoBtn])
        btnStack.orientation = .horizontal
        btnStack.spacing = 6
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [textField, btnStack])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            textField.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func sendPartial() {
        let text = textField.stringValue
        guard !text.isEmpty else { return }
        onPartial?(text)
    }

    @objc private func sendFinal() {
        let text = textField.stringValue
        guard !text.isEmpty else { return }
        onFinal?(text)
        textField.stringValue = ""
    }

    @objc private func toggleAuto() {
        if autoTimer != nil {
            autoTimer?.invalidate()
            autoTimer = nil
            autoBtn.title = "▶ Auto"
            autoIndex = 0
            autoWordIndex = 0
        } else {
            autoBtn.title = "⏹ Stop"
            autoIndex = 0
            autoWordIndex = 0
            playNextWord()
        }
    }

    private func playNextWord() {
        guard autoIndex < testSentences.count else {
            // Send final for last sentence then stop
            let sentence = testSentences[testSentences.count - 1]
            onFinal?(sentence)
            autoTimer?.invalidate()
            autoTimer = nil
            autoBtn.title = "▶ Auto"
            return
        }

        let sentence = testSentences[autoIndex]
        let words = sentence.split(separator: " ").map(String.init)

        // Build up word by word (simulates SFSpeechRecognizer partial)
        autoWordIndex += 1
        let partial = words.prefix(autoWordIndex).joined(separator: " ")
        textField.stringValue = partial
        onPartial?(partial)

        if autoWordIndex >= words.count {
            // Sentence done — send final, move to next
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.onFinal?(sentence)
                self.textField.stringValue = ""
                self.autoIndex += 1
                self.autoWordIndex = 0
                self.autoTimer?.invalidate()
                self.autoTimer = nil
                // Pause between sentences
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.playNextWord()
                }
            }
        } else {
            // Next word in 300ms
            autoTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.playNextWord()
            }
        }
    }
}
