import SwiftUI
import AppKit
import Combine

// MARK: - PhrasedWindowController

class PhrasedWindowController: NSWindowController, NSWindowDelegate {
    private static var activeScreen: NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private let inputVM: InputViewModel
    private let confirmVM: ConfirmViewModel
    private let hosting: NSHostingController<PhrasedView>
    private var cancellables = Set<AnyCancellable>()
    private(set) var pendingContext: InputContext = .empty
    private var mouseMonitor: Any?
    private var appShortcutMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private weak var cachedTextView: NSTextView?

    init(inputVM: InputViewModel, confirmVM: ConfirmViewModel) {
        self.inputVM = inputVM
        self.confirmVM = confirmVM

        let view = PhrasedView(inputVM: inputVM, confirmVM: confirmVM)
        let hosting = FirstMouseHostingController(rootView: view)
        self.hosting = hosting
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear

        let window = PhrasedPanel(
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
        inputVM.$inputText
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
            case "submit":      inputVM.submit();                         return true
            case "newline":     inputVM.insertNewline();                  return true
            case "pin":         confirmVM.isLocked.toggle();              return true
            case "edit":        confirmVM.showFeedbackField.toggle();     return true
            case "regenerate":  confirmVM.regenerate();                   return true
            case "inject":      confirmVM.accept(outputMode: inputVM.settings.defaultOutputMode); return true
            default: break
            }
        }
        return false
    }

    func showAndRecord(context: InputContext = .empty) {
        show(context: context)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !(self.inputVM.isRecording) else { return }
            self.inputVM.toggleRecording()
        }
    }

    private func positionNearCursor() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let visible = Self.activeScreen.visibleFrame
        let winW = window.frame.width
        let winH = window.frame.height

        // Center on cursor horizontally, place just below the cursor
        var x = mouse.x - winW / 2
        var y = mouse.y - winH - 12

        // If it would go below the visible area, flip above the cursor
        if y < visible.minY { y = mouse.y + 12 }

        // Clamp to visible area with a small margin
        x = max(visible.minX + 8, min(x, visible.maxX - winW - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - winH - 8))

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func updateWindowHeight(_ newHeight: CGFloat) {
        guard let window else { return }
        let visible = (window.screen ?? Self.activeScreen).visibleFrame
        let clamped = min(max(newHeight, 52), visible.height)
        var frame = window.frame

        let topEdge = frame.origin.y + frame.height
        let wouldBeBottom = topEdge - clamped

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
        // Register global mouse monitor: dismiss on click outside the panel
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.confirmVM.isLocked else { return }
            guard let win = self.window, !win.frame.contains(NSEvent.mouseLocation) else { return }
            DispatchQueue.main.async { self.dismissPanel() }
        }

        inputVM.cancelRecording()
        inputVM.inputText = context.selectedText ?? ""
        inputVM.editorHeight = 22
        positionNearCursor()
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
        tv.string = inputVM.inputText
        if !inputVM.inputText.isEmpty {
            tv.selectAll(nil)
        }
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
        confirmVM.streamTask?.cancel()
        window?.orderOut(nil)
        inputVM.contextAppName = nil
        inputVM.selectedTemplate = inputVM.allTemplates.first ?? PromptTemplate.builtins[0]
        confirmVM.streamedResult = ""
        confirmVM.streamError = nil
        confirmVM.showFeedbackField = false
        confirmVM.isLocked = false
        confirmVM.isStreaming = false
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }
}
