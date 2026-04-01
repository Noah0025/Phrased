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

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Intercept all clicks on finalized blocks so NSTextField doesn't consume them
        if isFinalized && bounds.contains(point) { return self }
        return super.hitTest(point)
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
    private var testInputHeight: CGFloat = 0

    // MARK: - Knowledge panel
    private let collapsedPanelWidth: CGFloat = 440
    private let expandedPanelWidth: CGFloat = 900
    private var isKnowledgeExpanded = false

    private let knowledgeContainer = NSView()
    private let knowledgeTitleLabel = NSTextField(labelWithString: "")
    private let knowledgeCloseButton = NSButton(title: "✕", target: nil, action: nil)
    private let knowledgeScrollView = NSScrollView()
    private let knowledgeTextView = NSTextView()

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

    // Height of the bottom bar region (separator + padding + button row + bottom margin)
    private let bottomBarHeight: CGFloat = 38
    private let pad: CGFloat = 12

    private func setupUI() {
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        contentView = visualEffect

        // --- Bottom control bar: frame-based layout (immune to auto-layout desync) ---
        bottomBar = NSView()
        bottomBar.translatesAutoresizingMaskIntoConstraints = true
        // Stick to the bottom of the contentView, stretch horizontally
        bottomBar.autoresizingMask = [.width, .maxYMargin]

        listeningIndicator.textColor = .systemRed
        listeningIndicator.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        listeningIndicator.translatesAutoresizingMaskIntoConstraints = true

        startButton.bezelStyle = .rounded
        startButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        startButton.target = self
        startButton.action = #selector(startButtonTapped)
        startButton.translatesAutoresizingMaskIntoConstraints = true

        cutButton.bezelStyle = .rounded
        cutButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        cutButton.target = self
        cutButton.action = #selector(cutButtonTapped)
        cutButton.isEnabled = false
        cutButton.translatesAutoresizingMaskIntoConstraints = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = true
        separator.autoresizingMask = [.width]

        [separator, listeningIndicator, startButton, cutButton].forEach {
            bottomBar.addSubview($0)
        }

        // --- Sentence scroll area (still auto-layout, pinned to top and bottom bar) ---
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
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        // Add scrollView first, then bottomBar on top
        visualEffect.addSubview(scrollView)
        visualEffect.addSubview(bottomBar)

        // --- Knowledge panel (right side, hidden until first click) ---
        knowledgeContainer.isHidden = true
        knowledgeContainer.translatesAutoresizingMaskIntoConstraints = true
        knowledgeContainer.wantsLayer = true
        knowledgeContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        knowledgeContainer.layer?.cornerRadius = 8

        knowledgeTitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        knowledgeTitleLabel.textColor = .labelColor
        knowledgeTitleLabel.translatesAutoresizingMaskIntoConstraints = true

        knowledgeCloseButton.bezelStyle = .rounded
        knowledgeCloseButton.font = NSFont.systemFont(ofSize: 11)
        knowledgeCloseButton.target = self
        knowledgeCloseButton.action = #selector(knowledgeCloseTapped)
        knowledgeCloseButton.translatesAutoresizingMaskIntoConstraints = true

        knowledgeTextView.isEditable = false
        knowledgeTextView.isSelectable = true
        knowledgeTextView.font = NSFont.systemFont(ofSize: 13)
        knowledgeTextView.textColor = .labelColor
        knowledgeTextView.backgroundColor = .clear
        knowledgeTextView.textContainerInset = NSSize(width: 4, height: 4)
        knowledgeTextView.isVerticallyResizable = true
        knowledgeTextView.isHorizontallyResizable = false

        knowledgeScrollView.documentView = knowledgeTextView
        knowledgeScrollView.hasVerticalScroller = true
        knowledgeScrollView.autohidesScrollers = true
        knowledgeScrollView.borderType = .noBorder
        knowledgeScrollView.backgroundColor = .clear
        knowledgeScrollView.drawsBackground = false
        knowledgeScrollView.translatesAutoresizingMaskIntoConstraints = true

        [knowledgeTitleLabel, knowledgeCloseButton, knowledgeScrollView]
            .forEach { knowledgeContainer.addSubview($0) }
        visualEffect.addSubview(knowledgeContainer)

        // Initial frame layout
        layoutBottomBar()
        layoutScrollView()
    }

    /// Lay out the bottom bar using explicit frames — no auto-layout involved.
    private func layoutBottomBar() {
        guard let cv = contentView else { return }
        let cvBounds = cv.bounds

        // Bottom bar frame: full width minus padding, pinned to bottom
        let barX = pad
        let barW = cvBounds.width - pad * 2
        bottomBar.frame = NSRect(x: barX, y: 10, width: barW, height: bottomBarHeight)

        // Separator at top of bottom bar
        let sep = bottomBar.subviews.first { $0 is NSBox }
        sep?.frame = NSRect(x: 0, y: bottomBarHeight - 1, width: barW, height: 1)

        // Listening indicator: bottom-left
        listeningIndicator.sizeToFit()
        listeningIndicator.frame.origin = NSPoint(x: 0, y: 0)

        // Cut button: bottom-right
        cutButton.sizeToFit()
        let cutW = max(cutButton.frame.width, 60)
        cutButton.frame = NSRect(x: barW - cutW, y: 0, width: cutW, height: cutButton.frame.height)

        // Start button: left of cut button
        startButton.sizeToFit()
        let startW = max(startButton.frame.width, 60)
        startButton.frame = NSRect(x: cutButton.frame.minX - startW - 6, y: 0, width: startW, height: startButton.frame.height)
    }

    /// Lay out the scroll view to fill the space between titlebar area and bottom bar.
    private func layoutScrollView() {
        guard let cv = contentView else { return }
        let cvBounds = cv.bounds
        let scrollTop = cvBounds.height - 28  // below titlebar

        // If test input exists, place it between scroll and bottom bar
        var scrollBottom = bottomBar.frame.maxY + 6
        if let tv = testInputView {
            let tvY = bottomBar.frame.maxY + 6
            tv.frame = NSRect(x: pad, y: tvY, width: cvBounds.width - pad * 2, height: testInputHeight)
            scrollBottom = tv.frame.maxY + 6
        }

        scrollView.frame = NSRect(
            x: pad,
            y: scrollBottom,
            width: cvBounds.width - pad * 2,
            height: max(scrollTop - scrollBottom, 0)
        )
    }

    /// Lay out left subtitle panel (1/3) and right knowledge panel (2/3) when expanded.
    private func layoutKnowledgePanel() {
        guard let cv = contentView else { return }
        let cvBounds = cv.bounds
        let totalWidth = cvBounds.width - pad * 2
        let divider: CGFloat = 8
        let leftWidth = (totalWidth - divider) / 3
        let rightWidth = totalWidth - leftWidth - divider
        let scrollBottom = bottomBar.frame.maxY + 6
        let contentHeight = max(cvBounds.height - 28 - scrollBottom, 0)

        // Subtitle scroll: left 1/3
        scrollView.frame = NSRect(x: pad, y: scrollBottom, width: leftWidth, height: contentHeight)

        // Knowledge container: right 2/3
        knowledgeContainer.frame = NSRect(
            x: pad + leftWidth + divider,
            y: scrollBottom,
            width: rightWidth,
            height: contentHeight
        )

        // Subviews inside knowledgeContainer (container-relative coords)
        let closeSize: CGFloat = 22
        let headerH: CGFloat = 26
        knowledgeCloseButton.frame = NSRect(
            x: rightWidth - closeSize - 2,
            y: contentHeight - headerH,
            width: closeSize, height: closeSize
        )
        knowledgeTitleLabel.frame = NSRect(
            x: 6,
            y: contentHeight - headerH,
            width: rightWidth - closeSize - 12, height: 20
        )
        knowledgeScrollView.frame = NSRect(
            x: 0, y: 0,
            width: rightWidth,
            height: contentHeight - headerH - 4
        )
        knowledgeTextView.frame = NSRect(
            x: 0, y: 0,
            width: rightWidth - 20,
            height: max(contentHeight - headerH - 4, 100)
        )
    }

    @objc private func startButtonTapped() {
        isRunning.toggle()
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
        guard isRunning else { return }
        onCut?()
    }

    func show() { orderFront(nil) }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        relayoutFrameBasedViews()
    }

    override func setFrame(_ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool) {
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
        relayoutFrameBasedViews()
    }

    private func relayoutFrameBasedViews() {
        layoutBottomBar()
        if isKnowledgeExpanded {
            layoutKnowledgePanel()
        } else {
            layoutScrollView()
        }
        let availableWidth = scrollView.frame.width
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

    // MARK: - Knowledge panel

    func showKnowledge(title: String, body: String) {
        DispatchQueue.main.async {
            self.knowledgeTitleLabel.stringValue = title
            self.knowledgeTextView.string = body
            self.knowledgeTextView.scrollToBeginningOfDocument(nil)

            if !self.isKnowledgeExpanded {
                self.isKnowledgeExpanded = true
                self.knowledgeContainer.isHidden = false
                var f = self.frame
                let diff = self.expandedPanelWidth - self.collapsedPanelWidth
                f.size.width = self.expandedPanelWidth
                f.origin.x -= diff
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.animator().setFrame(f, display: true)
                }
            }
        }
    }

    func hideKnowledge() {
        DispatchQueue.main.async {
            guard self.isKnowledgeExpanded else { return }
            self.isKnowledgeExpanded = false
            var f = self.frame
            let diff = self.expandedPanelWidth - self.collapsedPanelWidth
            f.size.width = self.collapsedPanelWidth
            f.origin.x += diff
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.animator().setFrame(f, display: true)
            }, completionHandler: {
                self.knowledgeContainer.isHidden = true
            })
        }
    }

    @objc private func knowledgeCloseTapped() {
        hideKnowledge()
    }

    // MARK: - Answer area (reserved for future separate window)

    // Stubs retained for AnswerFeature compatibility
    func appendAnswerChunk(_ chunk: String) {}
    func clearAnswer() {}
    func setAnswerLoading(_ loading: Bool) {}

    // MARK: - Test mode

    func addTestInput() -> TestInputView {
        let tv = TestInputView()
        tv.translatesAutoresizingMaskIntoConstraints = true
        tv.autoresizingMask = [.width, .maxYMargin]
        contentView!.addSubview(tv)
        testInputHeight = 72
        // Expand window to make room
        var f = frame
        f.size.height += 90
        setFrame(f, display: true)  // triggers relayoutFrameBasedViews
        testInputView = tv
        return tv
    }
}

