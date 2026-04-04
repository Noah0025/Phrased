import SwiftUI
import AppKit

@MainActor
class InputViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var editorHeight: CGFloat = 22
    @Published var isRecording: Bool = false
    @Published var isTranscribing: Bool = false
    @Published var selectedTemplate: PromptTemplate = PromptTemplate.builtins[0]
    @Published var allTemplates: [PromptTemplate] = PromptTemplate.builtins
    @Published var contextAppName: String? = nil

    var onSubmit: ((String, PromptTemplate) -> Void)?

    private let audioCapture = AudioCapture()
    private let micCapture = MicrophoneCapture()
    private var transcriber: ASRProvider
    private var pendingSubmit = false
    var settings: MurmurSettings = MurmurSettings()

    init(transcriber: ASRProvider = WhisperTranscriber()) {
        self.transcriber = transcriber
        transcriber.onFinal = { [weak self] text in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isTranscribing = false
                self.inputText = text
                if self.pendingSubmit {
                    self.pendingSubmit = false
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.onSubmit?(text, self.selectedTemplate)
                        self.inputText = ""
                    }
                }
            }
        }
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
        let finalText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else { return }
        onSubmit?(finalText, selectedTemplate)
        inputText = ""
    }

    func updateASRProvider(_ asr: ASRProvider) {
        transcriber = asr
    }

    func warmUpTranscriber() {
        transcriber.warmUp()
    }

    func toggleRecording() {
        isRecording ? stopRecordingManually() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        inputText = ""
        transcriber.startSession()
        if settings.audioSource == "microphone" {
            micCapture.start { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        } else {
            audioCapture.start { [weak self] buffer in
                self?.transcriber.appendBuffer(buffer)
            }
        }
    }

    private func stopRecordingManually() {
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        isTranscribing = true
        audioCapture.stop()
        micCapture.stop()
        transcriber.stopSession()
    }
}

// MARK: - WrappingTextView

/// NSTextView subclass that keeps textContainer width in sync with the view frame.
private class WrappingTextView: NSTextView {
    var onWidthChange: ((NSTextView) -> Void)?

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
}

// MARK: - AutoGrowingTextEditor

struct AutoGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var maxHeight: CGFloat = 160
    var font: NSFont = .systemFont(ofSize: 15)
    var onFocus: (() -> Void)?

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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = tv
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text {
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
