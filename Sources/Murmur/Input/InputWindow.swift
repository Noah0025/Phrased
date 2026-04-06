import SwiftUI
import AppKit
import Combine

@MainActor
class InputViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var editorHeight: CGFloat = 22
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var selectedTemplate: PromptTemplate = PromptTemplate.builtins[0]
    @Published var allTemplates: [PromptTemplate] = PromptTemplate.builtins
    @Published var contextAppName: String? = nil
    @Published var availableDevices: [AudioDevice] = []
    @Published var settings: MurmurSettings = MurmurSettings.loadOrDefault()

    var onSubmit: ((String, PromptTemplate) -> Void)?

    private let audioCapture = AudioCapture()
    private let micCapture = MicrophoneCapture()
    private var transcriber: ASRProvider
    private var pendingSubmit = false
    private var sessionGeneration: UInt64 = 0
    private let deviceManager = AudioDeviceManager()
    var vocabularyStore: VocabularyStore = VocabularyStore()

    // Silence auto-stop: if no partial result arrives within this interval, stop recording.
    private var silenceWorkItem: DispatchWorkItem?
    private let silenceTimeout: TimeInterval = 2.5

    // Transcribing timeout: if onFinal hasn't fired within this interval, clear the state.
    private var transcribingTimeoutItem: DispatchWorkItem?
    private let transcribingTimeout: TimeInterval = 2

    init(transcriber: ASRProvider = WhisperTranscriber()) {
        self.transcriber = transcriber
        availableDevices = deviceManager.devices
        deviceManager.$devices
            .receive(on: DispatchQueue.main)
            .assign(to: &$availableDevices)
        bindCallbacks(for: sessionGeneration)
    }

    private func bindCallbacks(for generation: UInt64) {
        transcriber.onPartial = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration, self.isRecording else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.inputText = text
                self.rescheduleSilenceTimer()
            }
        }
        transcriber.onFinal = { [weak self] text in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration else { return }
                self.cancelSilenceTimer()
                self.cancelTranscribingTimeout()
                self.isTranscribing = false
                self.inputText = text
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onSubmit?(text, self.selectedTemplate)
                    }
                }
            }
        }
        transcriber.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, generation == self.sessionGeneration else { return }
                print("[InputViewModel] Transcriber failed: \(error)")
                self.cancelSilenceTimer()
                self.cancelTranscribingTimeout()
                self.pendingSubmit = false
                self.isRecording = false
                self.isTranscribing = false
                self.audioCapture.stop()
                self.micCapture.stop()
                self.transcriber.stopSession()
            }
        }
    }

    private func rescheduleSilenceTimer() {
        cancelSilenceTimer()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.stopRecording()
            }
        }
        silenceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + silenceTimeout, execute: item)
    }

    private func cancelSilenceTimer() {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil
    }

    private func scheduleTranscribingTimeout() {
        transcribingTimeoutItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isTranscribing else { return }
                self.isTranscribing = false
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    let text = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { self.onSubmit?(text, self.selectedTemplate) }
                }
            }
        }
        transcribingTimeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + transcribingTimeout, execute: item)
    }

    private func cancelTranscribingTimeout() {
        transcribingTimeoutItem?.cancel()
        transcribingTimeoutItem = nil
    }

    /// Sets the active audio source and persists the preference.
    /// Falls back to "systemAudio" if the chosen device is no longer available.
    /// No-op during an active recording — takes effect on the next session.
    func selectAudioSource(_ id: String) {
        guard !isRecording else { return }
        let resolvedID = deviceManager.contains(id: id) ? id : "systemAudio"
        settings.audioSource = resolvedID
        do { try settings.save() } catch { print("[InputViewModel] Failed to save settings: \(error)") }
    }

    func submit() {
        if isRecording {
            pendingSubmit = true
            stopRecording()
            return
        }
        if isTranscribing {
            pendingSubmit = true
            return
        }
        let raw = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = vocabularyStore.apply(to: raw)
        guard !finalText.isEmpty else { return }
        onSubmit?(finalText, selectedTemplate)
    }

    func updateASRProvider(_ asr: ASRProvider) {
        transcriber = asr
        bindCallbacks(for: sessionGeneration)
    }

    func warmUpTranscriber() {
        transcriber.warmUp()
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        cancelSilenceTimer()
        pendingSubmit = false
        isRecording = true
        isTranscribing = false
        inputText = ""
        sessionGeneration &+= 1
        bindCallbacks(for: sessionGeneration)
        let generation = sessionGeneration
        transcriber.startSession()
        rescheduleSilenceTimer()
        if settings.audioSource == "systemAudio" {
            audioCapture.onError = { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self, generation == self.sessionGeneration else { return }
                    print("[InputViewModel] Audio capture failed: \(error)")
                    self.cancelSilenceTimer()
                    self.cancelTranscribingTimeout()
                    self.pendingSubmit = false
                    self.isRecording = false
                    self.isTranscribing = false
                    self.audioCapture.stop()
                    self.transcriber.stopSession()
                }
            }
            audioCapture.start { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        } else {
            let uid = settings.audioSource
            micCapture.onDeviceLost = { [weak self] in
                guard let self else { return }
                // Device disconnected mid-recording — stop cleanly.
                self.stopRecording()
            }
            do {
                try micCapture.start(deviceUID: uid) { [weak self] buffer in
                    self?.transcriber.appendBuffer(buffer)
                }
            } catch {
                print("[InputViewModel] Failed to start mic capture: \(error)")
                isRecording = false
                isTranscribing = false
                transcriber.stopSession()
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        cancelSilenceTimer()
        isRecording = false
        isTranscribing = true
        if settings.audioSource == "systemAudio" {
            audioCapture.stop()
        } else {
            micCapture.stop()
        }
        transcriber.stopSession()
        scheduleTranscribingTimeout()
    }

    /// Discard any in-progress recording without waiting for a final transcription result.
    func cancelRecording() {
        sessionGeneration &+= 1
        cancelSilenceTimer()
        cancelTranscribingTimeout()
        pendingSubmit = false
        isRecording = false
        isTranscribing = false
        audioCapture.stop()
        micCapture.stop()
        transcriber.stopSession()
    }
}

// MARK: - WrappingTextView

/// NSTextView subclass that keeps textContainer width in sync with the view frame.
private class WrappingTextView: NSTextView {
    var onWidthChange: ((NSTextView) -> Void)?
    var onCmdReturn: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard newSize.width > 0 else { return }
        let oldWidth = textContainer?.containerSize.width ?? 0
        guard abs(oldWidth - newSize.width) > 0.5 else { return }
        textContainer?.containerSize = NSSize(width: newSize.width, height: CGFloat.greatestFiniteMagnitude)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onWidthChange?(self)
        }
    }

    /// Explicitly handle standard text editing shortcuts.
    /// NSHostingView (SwiftUI wrapper) can intercept performKeyEquivalent before it
    /// reaches the first responder in some macOS/SwiftUI combinations; this override
    /// ensures Cmd+A/C/V/X/Z are handled directly on the text view.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let onlyCmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        guard onlyCmd else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers {
        case "a": selectAll(nil); return true
        case "c": copy(nil); return true
        case "v": paste(nil); return true
        case "x": cut(nil); return true
        case "z": undoManager?.undo(); return true
        case "\r": onCmdReturn?(); return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - AutoGrowingTextEditor

struct AutoGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxHeight: CGFloat = 160
    var font: NSFont = .systemFont(ofSize: 15)
    var onFocus: (() -> Void)?
    var onSubmit: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let tv = WrappingTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = font
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 1)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                  height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 0, height: 0)
        let coordinator = context.coordinator
        tv.onWidthChange = { [weak coordinator] textView in
            coordinator?.recalcHeight(textView)
        }
        tv.onCmdReturn = { [weak coordinator] in
            coordinator?.parent.onSubmit?()
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Skip overwrite while IME composition is in progress (marked text exists)
        if tv.string != text && tv.markedRange().length == 0 {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(sel)
        }
        DispatchQueue.main.async { self.recalcHeight(tv) }
    }

    func recalcHeight(_ tv: NSTextView) {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        lm.ensureLayout(for: tc)
        let contentH = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
        let clampedH = min(max(contentH, font.pointSize + 6), maxHeight)
        // editorHeight drives the NSScrollView's SwiftUI frame (clamped to maxHeight)
        if abs(clampedH - height) > 0.5 { height = clampedH }
        // tv frame must be full content height so NSScrollView can scroll when content > maxHeight
        if abs(tv.frame.height - contentH) > 0.5 {
            tv.setFrameSize(NSSize(width: tv.frame.width, height: contentH))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingTextEditor
        init(_ p: AutoGrowingTextEditor) { parent = p }

        func recalcHeight(_ tv: NSTextView) { parent.recalcHeight(tv) }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.recalcHeight(tv)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocus?()
        }
    }
}
