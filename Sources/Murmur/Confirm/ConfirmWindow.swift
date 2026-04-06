import SwiftUI
import AppKit
import Combine

// MARK: - MurmurPanel

/// NSPanel subclass that allows the panel to become the key window,
/// enabling ⌘V / ⌘A and other key equivalents to reach the text view.
private class MurmurPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var appShortcutHandler: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if appShortcutHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = FirstMouseHostingView(rootView: rootView)
    }
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
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(inputVM.isRecording ? .red : .secondary)
                .opacity(inputVM.isRecording && pulsing ? 0.35 : 1.0)
                .animation(
                    inputVM.isRecording
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .default,
                    value: pulsing
                )
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
            Text(inputVM.inputText)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        } else if inputVM.isTranscribing {
            HStack(alignment: .center, spacing: 6) {
                Text(inputVM.inputText)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
            }
            .contentShape(Rectangle())
            .onTapGesture { inputVM.cancelRecording() }
        } else {
            AutoGrowingTextEditor(
                text: $inputVM.inputText,
                height: $inputVM.editorHeight,
                onFocus: { inputVM.cancelRecording() },
                onSubmit: { inputVM.submit() }
            )
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

    // MARK: Submit button

    private var submitButton: some View {
        Button { inputVM.submit() } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isSubmitDisabled ? .secondary : .accentColor)
                .frame(width: 28, height: 28)
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
                .font(MurmurFont.ui)
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
            Button {
                confirmVM.isLocked.toggle()
            } label: {
                Image(systemName: confirmVM.isLocked ? "pin.fill" : "pin")
                    .font(MurmurFont.ui)
                    .foregroundColor(confirmVM.isLocked ? .accentColor : .secondary)
                    .rotationEffect(confirmVM.isLocked ? .degrees(-45) : .zero)
            }
            .buttonStyle(.plain)
            .help(confirmVM.isLocked ? "已锁定" : "锁定窗口")

            Text("风格")
                .font(MurmurFont.ui)
                .foregroundColor(.secondary)

            stylePicker

            Spacer()

            Button { confirmVM.showFeedbackField.toggle() } label: {
                Image(systemName: "square.and.pencil")
                    .font(MurmurFont.ui)
                    .foregroundColor(.secondary)
            }
            .disabled(confirmVM.isStreaming)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .help("修改意见")

            Button { confirmVM.regenerate() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(MurmurFont.ui)
                    .foregroundColor(.secondary)
            }
            .disabled(confirmVM.isStreaming)
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            .help("重新生成")

            let acceptLabel = confirmVM.didCopy ? "已注入" : "注入"
            Button(acceptLabel) { confirmVM.accept(outputMode: "inject") }
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
    private(set) var pendingContext: InputContext = .empty
    private var mouseMonitor: Any?
    private var appShortcutMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private weak var cachedTextView: NSTextView?

    init(inputVM: InputViewModel, confirmVM: ConfirmViewModel) {
        self.inputVM = inputVM
        self.confirmVM = confirmVM

        let view = MurmurView(inputVM: inputVM, confirmVM: confirmVM)
        let hosting = FirstMouseHostingController(rootView: view)
        self.hosting = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear

        let window = MurmurPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
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
        window.appShortcutHandler = { [weak self] event in
            self?.handleAppShortcut(event) ?? false
        }

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

        // After transcription finishes, AutoGrowingTextEditor re-enters the view hierarchy
        // but NSTextView isn't automatically made first responder. Re-focus it so that
        // the Cmd+Return override in WrappingTextView can fire immediately.
        inputVM.$isTranscribing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isTranscribing in
                guard let self, !isTranscribing else { return }
                // Wait one run loop for SwiftUI to re-render AutoGrowingTextEditor into hierarchy.
                DispatchQueue.main.async { self.focusTextView() }
            }
            .store(in: &cancellables)

        confirmVM.onDismiss = { [weak self] in
            self?.dismissPanel()
        }

        // Dismiss when the user switches to a real app (⌘Tab, clicking another app's window).
        // NSWorkspace.didActivateApplicationNotification fires only for actual applications,
        // NOT for IME candidate windows or clipboard operations — solving all false-dismiss bugs.
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, !self.confirmVM.isLocked else { return }
            guard self.window?.isVisible == true else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            self.dismissPanel()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
        if let m = appShortcutMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - In-app shortcut wiring

    func installAppShortcutMonitor() {
        if appShortcutMonitor != nil { return }
        appShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true else { return event }
            return self.handleAppShortcut(event) ? nil : event
        }
    }

    private func handleAppShortcut(_ event: NSEvent) -> Bool {
        let shortcuts = inputVM.settings.appShortcuts
        let relevantMods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let eventMods = event.modifierFlags.intersection(relevantMods)

        for shortcut in shortcuts {
            // Skip "disabled" shortcuts (empty = UInt16.max with no modifiers)
            guard shortcut.keyCode != UInt16.max || !shortcut.modifiers.isEmpty else { continue }
            // Skip modifier-only shortcuts (shouldn't appear in app shortcuts, but guard anyway)
            guard shortcut.keyCode != UInt16.max else { continue }
            guard event.keyCode == shortcut.keyCode else { continue }
            let shortcutMods = shortcut.modifiers.reduce(NSEvent.ModifierFlags()) { flags, mod in
                switch mod {
                case "command": return flags.union(.command)
                case "option":  return flags.union(.option)
                case "control": return flags.union(.control)
                case "shift":   return flags.union(.shift)
                default:        return flags
                }
            }
            guard eventMods == shortcutMods else { continue }

            switch shortcut.id {
            case "transcribe":  inputVM.toggleRecording();                return true
            case "pin":         confirmVM.isLocked.toggle();              return true
            case "edit":        confirmVM.showFeedbackField.toggle();     return true
            case "regenerate":  confirmVM.regenerate();                   return true
            case "inject":      confirmVM.accept(outputMode: "inject");   return true
            default: break
            }
        }
        return false
    }

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

    // Dismiss is handled by: NSWorkspace.didActivateApplicationNotification (app switch / ⌘Tab)
    // and the global mouse monitor (click outside). windowDidResignKey is intentionally unused
    // because it fires spuriously during IME candidate window repositioning and window resizes.

    func windowDidBecomeKey(_ notification: Notification) {
        // Don't steal first responder while recording — doing so interrupts button tracking
        // and causes the stop button click to be swallowed.
        guard !inputVM.isRecording else { return }

        // Re-focus the input text view whenever the panel gains key status.
        guard let tv = textView(),
              window?.firstResponder !== tv else { return }
        window?.makeFirstResponder(tv)
    }

    func updateTemplates(_ templates: [PromptTemplate]) {
        inputVM.allTemplates = templates
        if let updated = templates.first(where: { $0.id == inputVM.selectedTemplate.id }) {
            inputVM.selectedTemplate = updated
        } else {
            inputVM.selectedTemplate = templates.first ?? PromptTemplate.builtins[0]
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
        // Register global mouse monitor: dismiss on click outside the panel
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.confirmVM.isLocked else { return }
            guard let win = self.window, !win.frame.contains(NSEvent.mouseLocation) else { return }
            DispatchQueue.main.async { self.dismissPanel() }
        }

        inputVM.cancelRecording()
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
    }

    private func syncAndFocusTextView() {
        guard let tv = textView() else { return }
        tv.string = ""
        window?.makeFirstResponder(tv)
    }

    private func focusTextView() {
        guard let tv = textView() else { return }
        window?.makeFirstResponder(tv)
    }

    private func textView() -> NSTextView? {
        if let tv = cachedTextView, tv.superview != nil { return tv }
        cachedTextView = findTextView(in: window?.contentView)
        return cachedTextView
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let tv = view as? NSTextView { return tv }
        return view.subviews.lazy.compactMap { self.findTextView(in: $0) }.first
    }

    private func dismissPanel() {
        inputVM.cancelRecording()
        window?.orderOut(nil)
        inputVM.contextAppName = nil
        confirmVM.streamedResult = ""
        confirmVM.showFeedbackField = false
        confirmVM.isLocked = false
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }
}
