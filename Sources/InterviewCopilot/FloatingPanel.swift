import AppKit

// MARK: - Sentence Pair View (Clickable Block)

class SentencePairView: NSView {
    private let enLabel = NSTextField(wrappingLabelWithString: "")
    private let zhLabel = NSTextField(wrappingLabelWithString: "")
    private var trackingArea: NSTrackingArea?

    var onBlockClicked: ((String, String) -> Void)?
    var metadata: [String: Any] = [:]

    private(set) var isFinalized = false
    private(set) var enText: String = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor

        enLabel.font = NSFont.systemFont(ofSize: 12)
        enLabel.textColor = .secondaryLabelColor
        enLabel.isEditable = false
        enLabel.isSelectable = true
        enLabel.isBordered = false
        enLabel.backgroundColor = .clear
        enLabel.lineBreakMode = .byWordWrapping
        enLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enLabel.translatesAutoresizingMaskIntoConstraints = false

        zhLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        zhLabel.textColor = .labelColor
        zhLabel.isEditable = false
        zhLabel.isSelectable = true
        zhLabel.isBordered = false
        zhLabel.backgroundColor = .clear
        zhLabel.lineBreakMode = .byWordWrapping
        zhLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zhLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(enLabel)
        addSubview(zhLabel)

        NSLayoutConstraint.activate([
            enLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            enLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            enLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            zhLabel.topAnchor.constraint(equalTo: enLabel.bottomAnchor, constant: 2),
            zhLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            zhLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            zhLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        guard isFinalized else { return }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = isFinalized
            ? NSColor.white.withAlphaComponent(0.04).cgColor
            : NSColor.white.withAlphaComponent(0.04).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        guard isFinalized else { return }
        onBlockClicked?(enText, zhLabel.stringValue)
    }

    func updateEN(_ text: String) {
        enText = text
        enLabel.stringValue = text
    }

    func setZH(_ text: String) {
        zhLabel.stringValue = text
    }

    func appendZH(_ chunk: String) {
        let clean = chunk.replacingOccurrences(of: "\n", with: "")
        guard !clean.isEmpty else { return }
        zhLabel.stringValue += clean
    }

    func markFinalized() {
        isFinalized = true
        enLabel.textColor = .tertiaryLabelColor
        zhLabel.textColor = .secondaryLabelColor
        zhLabel.font = NSFont.systemFont(ofSize: 13)
    }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    var onBlockClicked: ((String, String, [String: Any]) -> Void)?
    var onStartStop: ((Bool) -> Void)?   // true = start, false = stop
    var onCut: (() -> Void)?             // cut sentence

    private let listeningIndicator = NSTextField(labelWithString: "● Not listening")
    private let sentenceStack = NSStackView()
    private let scrollView = NSScrollView()
    private let startButton = NSButton(title: "▶ 开始", target: nil, action: nil)
    private let cutButton = NSButton(title: "✂ 断句", target: nil, action: nil)

    private(set) var testInputView: TestInputView?
    private var activePair: SentencePairView?
    private let panelWidth: CGFloat = 440
    private var isRunning = false
    private var stackWidthConstraint: NSLayoutConstraint?
    private var bottomBar: NSView!
    private var scrollBottomConstraint: NSLayoutConstraint!

    init() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelHeight: CGFloat = 320
        let origin = NSPoint(
            x: screenFrame.maxX - panelWidth - 20,
            y: screenFrame.minY + 60
        )
        let frame = NSRect(origin: origin, size: CGSize(width: panelWidth, height: panelHeight))

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.minSize = NSSize(width: 320, height: 200)

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        self.isReleasedWhenClosed = false
        setupUI()
    }

    // Prevent close — just hide
    override func close() {
        orderOut(nil)
    }

    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        contentView = visualEffect

        let pad: CGFloat = 12

        // --- Bottom control bar (in its own container, always on top) ---
        bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        listeningIndicator.textColor = .systemRed
        listeningIndicator.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        listeningIndicator.translatesAutoresizingMaskIntoConstraints = false

        startButton.bezelStyle = .rounded
        startButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        startButton.target = self
        startButton.action = #selector(startButtonTapped)
        startButton.translatesAutoresizingMaskIntoConstraints = false

        cutButton.bezelStyle = .rounded
        cutButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cutButton.target = self
        cutButton.action = #selector(cutButtonTapped)
        cutButton.isEnabled = false
        cutButton.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        [separator, listeningIndicator, startButton, cutButton].forEach {
            bottomBar.addSubview($0)
        }

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: bottomBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),

            listeningIndicator.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            listeningIndicator.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor),
            listeningIndicator.bottomAnchor.constraint(equalTo: bottomBar.bottomAnchor),

            cutButton.centerYAnchor.constraint(equalTo: listeningIndicator.centerYAnchor),
            cutButton.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor),

            startButton.centerYAnchor.constraint(equalTo: listeningIndicator.centerYAnchor),
            startButton.trailingAnchor.constraint(equalTo: cutButton.leadingAnchor, constant: -6),
        ])

        // --- Sentence scroll area ---
        sentenceStack.orientation = .vertical
        sentenceStack.alignment = .left
        sentenceStack.spacing = 6
        sentenceStack.translatesAutoresizingMaskIntoConstraints = false

        stackWidthConstraint = sentenceStack.widthAnchor.constraint(equalToConstant: panelWidth - 24)
        stackWidthConstraint?.isActive = true

        scrollView.documentView = sentenceStack
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false

        // Add scrollView first, then bottomBar on top
        visualEffect.addSubview(scrollView)
        visualEffect.addSubview(bottomBar)

        scrollBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6)

        NSLayoutConstraint.activate([
            // Bottom bar pinned to bottom
            bottomBar.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: pad),
            bottomBar.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -pad),
            bottomBar.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -10),

            // Scroll area fills from top to bottom bar
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 28),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: pad),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -pad),
            scrollBottomConstraint,
        ])
    }

    @objc private func startButtonTapped() {
        isRunning.toggle()
        logDebug("[UI] startButton tapped, isRunning=\(isRunning)")
        if isRunning {
            startButton.title = "⏸ 暂停"
            cutButton.isEnabled = true
            listeningIndicator.stringValue = "● Listening..."
            listeningIndicator.textColor = .systemGreen
            onStartStop?(true)
        } else {
            startButton.title = "▶ 开始"
            cutButton.isEnabled = false
            listeningIndicator.stringValue = "● Not listening"
            listeningIndicator.textColor = .systemRed
            onStartStop?(false)
        }
    }

    @objc private func cutButtonTapped() {
        logDebug("[UI] cutButton tapped, isRunning=\(isRunning)")
        guard isRunning else { return }
        onCut?()
    }

    func show() { orderFront(nil) }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let loc = event.locationInWindow
            // Log in startButton's superview (bottomBar) coordinate space
            let startInWindow = startButton.superview?.convert(startButton.frame, to: nil) ?? .zero
            let cutInWindow = cutButton.superview?.convert(cutButton.frame, to: nil) ?? .zero
            logDebug("[Event] click at \(loc) startBtn(window)=\(startInWindow) cutBtn(window)=\(cutInWindow)")
        }
        super.sendEvent(event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        updateStackWidth()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
        updateStackWidth()
    }

    private func updateStackWidth() {
        let availableWidth = scrollView.contentView.bounds.width
        guard availableWidth > 0 else { return }
        stackWidthConstraint?.constant = availableWidth
    }

    // MARK: - Active pair text access

    func currentActiveEN() -> String? {
        return activePair?.enText
    }

    func sentenceStackViews() -> [SentencePairView] {
        return sentenceStack.arrangedSubviews.compactMap { $0 as? SentencePairView }
    }

    // MARK: - Sentence pair management

    private var scrollPending = false

    private func ensureActivePair() {
        // Must be called on main thread
        guard activePair == nil else { return }
        let pair = SentencePairView()
        pair.translatesAutoresizingMaskIntoConstraints = false
        sentenceStack.addArrangedSubview(pair)
        pair.widthAnchor.constraint(equalTo: sentenceStack.widthAnchor).isActive = true
        activePair = pair
        scheduleScroll()
    }

    func updateSubtitleEN(_ text: String) {
        DispatchQueue.main.async {
            self.ensureActivePair()
            self.activePair?.updateEN(text)
            // No scroll — EN text update doesn't change layout height significantly
        }
    }

    func updateSubtitleZH(_ text: String) {
        DispatchQueue.main.async {
            self.ensureActivePair()
            self.activePair?.setZH(text)
            self.scheduleScroll()
        }
    }

    func appendSubtitleZH(_ chunk: String) {
        DispatchQueue.main.async {
            self.ensureActivePair()
            self.activePair?.appendZH(chunk)
            self.scheduleScroll()
        }
    }

    /// Merge a pair into the previous finalized pair.
    /// Combines EN text, replaces ZH, removes the merged pair from stack.
    /// Returns the previous pair (now updated) for re-translation.
    func mergeIntoPrevious(pair: SentencePairView, combinedZH: String) {
        let views = sentenceStack.arrangedSubviews.compactMap { $0 as? SentencePairView }
        guard let idx = views.firstIndex(where: { $0 === pair }),
              idx > 0 else {
            // No previous pair to merge into — just finalize
            pair.markFinalized()
            return
        }
        let prevPair = views[idx - 1]
        let combinedEN = prevPair.enText + " " + pair.enText
        prevPair.updateEN(combinedEN)
        prevPair.setZH(combinedZH)
        // Remove the merged pair
        sentenceStack.removeArrangedSubview(pair)
        pair.removeFromSuperview()
        scheduleScroll()
    }

    func detachActivePair() -> SentencePairView? {
        guard let pair = activePair else { return nil }
        pair.onBlockClicked = { [weak self] en, zh in
            self?.onBlockClicked?(en, zh, pair.metadata)
        }
        activePair = nil
        trimPairs()
        return pair
    }

    /// Replace the last `count` finalized pairs with new pairs.
    /// Used for context-aware re-segmentation.
    func replaceRecentPairs(count: Int, with pairs: [(en: String, zh: String)]) {
        DispatchQueue.main.async {
            let views = self.sentenceStack.arrangedSubviews
            // Only replace finalized pairs (not active)
            let finalized = views.filter { ($0 as? SentencePairView)?.isFinalized == true }
            let toRemove = finalized.suffix(count)
            for view in toRemove {
                self.sentenceStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            // Add new properly-segmented pairs
            for p in pairs {
                let pair = SentencePairView()
                pair.translatesAutoresizingMaskIntoConstraints = false
                pair.updateEN(p.en)
                pair.setZH(p.zh)
                pair.markFinalized()
                pair.onBlockClicked = { [weak self] en, zh in
                    self?.onBlockClicked?(en, zh, pair.metadata)
                }
                // Insert before activePair if it exists
                if let active = self.activePair,
                   let idx = self.sentenceStack.arrangedSubviews.firstIndex(of: active) {
                    self.sentenceStack.insertArrangedSubview(pair, at: idx)
                } else {
                    self.sentenceStack.addArrangedSubview(pair)
                }
                pair.widthAnchor.constraint(equalTo: self.sentenceStack.widthAnchor).isActive = true
            }
            self.scheduleScroll()
        }
    }

    func finalizeCurrentPair() {
        DispatchQueue.main.async {
            guard let pair = self.activePair else { return }
            pair.markFinalized()
            pair.onBlockClicked = { [weak self] en, zh in
                self?.onBlockClicked?(en, zh, pair.metadata)
            }
            self.activePair = nil
            self.trimPairs()
            self.scheduleScroll()
        }
    }

    func clearAllPairs() {
        DispatchQueue.main.async {
            for view in self.sentenceStack.arrangedSubviews {
                self.sentenceStack.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            self.activePair = nil
        }
    }

    func addRenderedPair(en: String, zh: String, finalized: Bool) {
        DispatchQueue.main.async {
            let pair = SentencePairView()
            pair.translatesAutoresizingMaskIntoConstraints = false
            pair.updateEN(en)
            if !zh.isEmpty { pair.setZH(zh) }
            if finalized {
                pair.markFinalized()
                pair.onBlockClicked = { [weak self] en, zh in
                    self?.onBlockClicked?(en, zh, pair.metadata)
                }
            }
            self.sentenceStack.addArrangedSubview(pair)
            pair.widthAnchor.constraint(equalTo: self.sentenceStack.widthAnchor).isActive = true
            if !finalized { self.activePair = pair }
            self.scheduleScroll()
        }
    }

    private func trimPairs() {
        let views = self.sentenceStack.arrangedSubviews
        if views.count > 8 {
            views.prefix(views.count - 8).forEach {
                self.sentenceStack.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        }
    }

    /// Throttled scroll — coalesces requests, waits for layout, scrolls last view into sight
    private func scheduleScroll() {
        guard !scrollPending else { return }
        scrollPending = true
        // Use afterDelay to ensure layout has settled
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.scrollPending = false
            self.sentenceStack.layoutSubtreeIfNeeded()
            if let lastView = self.sentenceStack.arrangedSubviews.last {
                lastView.scrollToVisible(lastView.bounds)
            }
        }
    }

    // MARK: - Listening state

    func setListeningState(_ listening: Bool) {
        DispatchQueue.main.async {
            self.listeningIndicator.stringValue = listening ? "● Listening..." : "● Not listening"
            self.listeningIndicator.textColor = listening ? .systemGreen : .systemRed
        }
    }

    // MARK: - Answer area (reserved for future separate window)

    func appendAnswerChunk(_ chunk: String) {}
    func clearAnswer() {}
    func setAnswerLoading(_ loading: Bool) {}

    // MARK: - Test mode

    func addTestInput() -> TestInputView {
        let tv = TestInputView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 12),
            tv.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -12),
            tv.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -6),
            tv.heightAnchor.constraint(equalToConstant: 72),
        ])
        // Reconnect scrollView bottom to test input instead of bottomBar
        scrollBottomConstraint.isActive = false
        scrollView.bottomAnchor.constraint(equalTo: tv.topAnchor, constant: -6).isActive = true
        var f = frame
        f.size.height += 90
        setFrame(f, display: true)
        testInputView = tv
        return tv
    }
}

