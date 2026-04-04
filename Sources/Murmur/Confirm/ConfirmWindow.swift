import SwiftUI
import AppKit
import Combine

// MARK: - MurmurPanel

/// NSPanel subclass that allows the panel to become the key window,
/// enabling ⌘V / ⌘A and other key equivalents to reach the text view.
private class MurmurPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - MurmurView

struct MurmurView: View {
    @ObservedObject var inputVM: InputViewModel
    @ObservedObject var confirmVM: ConfirmViewModel

    // editorHeight lives in InputViewModel so MurmurWindowController can observe it
    @State private var pulsing = false
    @State private var showCursor = true
    @FocusState private var feedbackFocused: Bool

    private var showResult: Bool {
        confirmVM.isStreaming || !confirmVM.streamedResult.isEmpty
    }
    private var isSubmitDisabled: Bool {
        inputVM.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !inputVM.isRecording && !inputVM.isTranscribing
    }

    var body: some View {
        VStack(spacing: 0) {
            if let appName = inputVM.contextAppName {
                HStack(spacing: 4) {
                    Image(systemName: "app.badge")
                        .font(.caption2).foregroundColor(.secondary.opacity(0.5))
                    Text(appName)
                        .font(.caption2).foregroundColor(.secondary.opacity(0.6))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            inputBar

            if showResult {
                Divider()
                resultArea
                if confirmVM.showFeedbackField {
                    Divider()
                    feedbackArea
                }
                Divider()
                actionBar
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    inputVM.isRecording ? Color.red.opacity(0.4) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
        .frame(width: 500)
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: showResult)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: confirmVM.showFeedbackField)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if confirmVM.isStreaming { showCursor.toggle() } else { showCursor = false }
        }
        .onChange(of: inputVM.selectedTemplate) { newTemplate in
            guard showResult else { return }
            confirmVM.start(input: confirmVM.originalInput, template: newTemplate)
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            micButton
                .padding(.leading, 10)
                .padding(.bottom, 9)

            inputArea
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

            stylePicker
                .padding(.bottom, 7)

            audioSourceButton
                .padding(.bottom, 7)

            Spacer().frame(width: 12)

            submitButton
                .padding(.trailing, 10)
                .padding(.bottom, 9)
        }
    }

    // MARK: Mic button

    private var micButton: some View {
        Button {
            inputVM.toggleRecording()
        } label: {
            Image(systemName: inputVM.isRecording ? "stop.fill" : "waveform")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(inputVM.isRecording ? .red : .secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(inputVM.isRecording ? "停止录音" : "开始录音")
        .onChange(of: inputVM.isRecording) { pulsing = $0 }
    }

    // MARK: Input area

    @ViewBuilder
    private var inputArea: some View {
        if inputVM.isRecording {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulsing ? 1.8 : 1.0)
                        .opacity(pulsing ? 0 : 1)
                        .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: pulsing)
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
                .onAppear { pulsing = true }
                .onDisappear { pulsing = false }
                Text("正在聆听...")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else if inputVM.isTranscribing {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
                Text("正在识别...")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else {
            AutoGrowingTextEditor(text: $inputVM.inputText, height: $inputVM.editorHeight)
                .frame(height: inputVM.editorHeight)
                .clipped()
        }
    }

    // MARK: Style picker

    private var stylePicker: some View {
        Picker("", selection: $inputVM.selectedTemplate) {
            ForEach(inputVM.allTemplates) { t in
                Text(t.name).tag(t)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 88)
        .labelsHidden()
    }

    // MARK: Audio source button

    private var audioSourceButton: some View {
        Button {
            inputVM.settings.audioSource = inputVM.settings.audioSource == "microphone" ? "systemAudio" : "microphone"
        } label: {
            Text(inputVM.settings.audioSource == "microphone" ? "🎙" : "🖥")
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(inputVM.settings.audioSource == "microphone" ? "当前：麦克风" : "当前：系统音频")
    }

    // MARK: Submit button

    private var submitButton: some View {
        Button { inputVM.submit() } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isSubmitDisabled ? .secondary.opacity(0.4) : .white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isSubmitDisabled ? Color.primary.opacity(0.06) : Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitDisabled)
        .keyboardShortcut(.return, modifiers: .command)
    }

    // MARK: Result area

    private var resultArea: some View {
        HStack(alignment: .top, spacing: 0) {
            Group {
                if confirmVM.streamedResult.isEmpty && confirmVM.isStreaming {
                    Text("正在生成...")
                        .foregroundColor(.secondary)
                } else {
                    Text(confirmVM.streamedResult)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .leading)

            if confirmVM.isStreaming {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 18)
                    .opacity(showCursor ? 1 : 0)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 52)
    }

    // MARK: Feedback area

    private var feedbackArea: some View {
        HStack(spacing: 8) {
            TextField("说明哪里不对，或想要什么效果...", text: $confirmVM.feedbackText)
                .font(.system(size: 13))
                .textFieldStyle(.roundedBorder)
                .focused($feedbackFocused)
            Button("生成") { confirmVM.regenerate() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(confirmVM.isStreaming)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { feedbackFocused = true }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 6) {
            Button("修改意见") { confirmVM.showFeedbackField.toggle() }
                .disabled(confirmVM.isStreaming)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Spacer()

            Button {
                confirmVM.isLocked.toggle()
            } label: {
                Image(systemName: confirmVM.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13))
                    .foregroundColor(confirmVM.isLocked ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(confirmVM.isLocked ? "已锁定" : "锁定窗口")

            Button("重新生成") { confirmVM.regenerate() }
                .disabled(confirmVM.isStreaming)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))

            let outputMode = inputVM.settings.defaultOutputMode
            let accepted = confirmVM.didCopy
            let acceptLabel = accepted
                ? (outputMode == "inject" ? "已注入 ✓" : "已复制 ✓")
                : (outputMode == "inject" ? "注入到光标" : "接受并复制")
            Button(acceptLabel) { confirmVM.accept(outputMode: outputMode) }
                .keyboardShortcut(.return)
                .disabled(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty)
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty ? .secondary : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(confirmVM.isStreaming || confirmVM.streamedResult.isEmpty
                              ? Color.primary.opacity(0.08)
                              : Color.accentColor)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - MurmurWindowController

class MurmurWindowController: NSWindowController, NSWindowDelegate {
    private let inputVM: InputViewModel
    private let confirmVM: ConfirmViewModel
    private let hosting: NSHostingController<MurmurView>
    private var cancellables = Set<AnyCancellable>()
    private var isBeingShown = false
    private(set) var pendingContext: InputContext = .empty

    init(inputVM: InputViewModel, confirmVM: ConfirmViewModel) {
        self.inputVM = inputVM
        self.confirmVM = confirmVM

        let view = MurmurView(inputVM: inputVM, confirmVM: confirmVM)
        let hosting = NSHostingController(rootView: view)
        self.hosting = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear

        let window = MurmurPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 52),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
        window.contentViewController = hosting
        window.isFloatingPanel = true
        window.level = .floating
        window.hasShadow = true
        window.center()
        super.init(window: window)
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Subscribe to the three properties that drive window height changes.
        // Double-async ensures SwiftUI has finished layout before we measure.
        let resize: () -> Void = { [weak self, weak hosting] in
            DispatchQueue.main.async {
                guard let self, let hosting else { return }
                let ideal = hosting.sizeThatFits(in: NSSize(width: 500, height: 10000))
                guard ideal.height > 0 else { return }
                self.updateWindowHeight(ideal.height)
            }
        }
        inputVM.$editorHeight
            .receive(on: DispatchQueue.main).sink { _ in resize() }.store(in: &cancellables)
        confirmVM.$streamedResult
            .receive(on: DispatchQueue.main).sink { _ in resize() }.store(in: &cancellables)
        confirmVM.$showFeedbackField
            .receive(on: DispatchQueue.main).sink { _ in resize() }.store(in: &cancellables)

        confirmVM.onDismiss = { [weak self] in
            self?.window?.orderOut(nil)
            confirmVM.streamedResult = ""
            confirmVM.showFeedbackField = false
            confirmVM.isLocked = false
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateWindowHeight(_ newHeight: CGFloat) {
        guard let window else { return }
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let clamped = min(max(newHeight, 52), visible.height)
        var frame = window.frame

        let topEdge = frame.origin.y + frame.height  // current top (stays fixed by default)
        let wouldBeBottom = topEdge - clamped         // new bottom if we keep top fixed

        if wouldBeBottom >= visible.origin.y {
            // Growing downward fits — keep top fixed
            frame.origin.y = wouldBeBottom
        } else {
            // Growing downward would go below Dock — keep current bottom fixed, grow upward
            let bottomEdge = frame.origin.y
            let wouldBeTop = bottomEdge + clamped
            if wouldBeTop > visible.maxY {
                // Also exceeds menu bar — anchor top to menu bar edge
                frame.origin.y = visible.maxY - clamped
            }
            // else: origin.y unchanged — window grows upward from where it sits
        }
        frame.size.height = clamped
        window.setFrame(frame, display: true, animate: false)
    }

    func updateTemplates(_ templates: [PromptTemplate]) {
        inputVM.allTemplates = templates
        if !templates.contains(inputVM.selectedTemplate) {
            inputVM.selectedTemplate = PromptTemplate.builtins[0]
        }
    }

    func show(context: InputContext = .empty) {
        pendingContext = context
        inputVM.contextAppName = context.frontmostAppName
        // Auto-apply suggested template based on frontmost app
        if let suggestedID = context.suggestedTemplateID,
           let template = inputVM.allTemplates.first(where: { $0.id == suggestedID }) {
            inputVM.selectedTemplate = template
        }
        isBeingShown = true
        inputVM.inputText = ""
        inputVM.editorHeight = 22
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        // activate is async; defer makeKey to next run loop so activation completes first
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.syncAndFocusTextView()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isBeingShown = false
        }
    }

    private func syncAndFocusTextView() {
        guard let root = window?.contentView,
              let tv = findTextView(in: root) else { return }
        tv.string = ""
        window?.makeFirstResponder(tv)
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isBeingShown, !confirmVM.isLocked else { return }
        window?.orderOut(nil)
        confirmVM.streamedResult = ""
        confirmVM.showFeedbackField = false
        confirmVM.isLocked = false
    }
}
