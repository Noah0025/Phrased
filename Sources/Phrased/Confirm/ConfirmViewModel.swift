import Foundation
import Combine
import AppKit

@MainActor
class ConfirmViewModel: ObservableObject {
    @Published var originalInput: String = ""
    @Published var streamedResult: String = ""
    @Published var streamError: String? = nil
    @Published var isStreaming: Bool = false
    @Published var feedbackText: String = ""
    @Published var showFeedbackField: Bool = false
    @Published var didCopy: Bool = false
    @Published var isLocked: Bool = false
    private(set) var currentTemplate: PromptTemplate = PromptTemplate.builtins[0]
    private(set) var currentContext: InputContext = .empty

    private var llm: LLMProvider
    private let processor: IntentProcessor
    private let historyStore: HistoryStore
    private var streamTask: Task<Void, Never>?
    private var chunkBuffer = ""
    private var flushTimer: DispatchSourceTimer?

    var settings: PhrasedSettings = .loadOrDefault()
    var onDismiss: (() -> Void)?

    init(llm: LLMProvider, processor: IntentProcessor, historyStore: HistoryStore = HistoryStore()) {
        self.llm = llm
        self.processor = processor
        self.historyStore = historyStore
    }

    func updateProvider(_ newLLM: LLMProvider) {
        llm = newLLM
    }

    func start(input: String, template: PromptTemplate = PromptTemplate.builtins[0], context: InputContext = .empty) {
        originalInput = input
        currentTemplate = template
        currentContext = context
        stopChunkBuffering()
        streamedResult = ""
        streamError = nil
        feedbackText = ""
        showFeedbackField = false
        didCopy = false
        generate(feedback: nil)
    }

    func regenerate() {
        let feedback = feedbackText.isEmpty ? nil : feedbackText
        stopChunkBuffering()
        streamedResult = ""
        streamError = nil
        showFeedbackField = false
        feedbackText = ""
        generate(feedback: feedback)
    }

    func accept(outputMode: OutputMode = .copy) {
        let text = streamedResult
        let targetApp = currentContext.frontmostApp

        // Persist to history
        let entry = HistoryEntry(
            id: UUID(), createdAt: Date(),
            input: originalInput, output: text,
            templateName: currentTemplate.name,
            appName: currentContext.frontmostAppName
        )
        try? historyStore.append(entry)

        if outputMode == .inject {
            Task { @MainActor in
                await TextInjector.inject(text, into: targetApp)
            }
        } else {
            ClipboardOutput.copy(text)
        }

        didCopy = true
        if !isLocked {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.onDismiss?()
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        stopChunkBuffering()
        isLocked = false
        onDismiss?()
    }

    private func generate(feedback: String?) {
        streamTask?.cancel()
        stopChunkBuffering()
        isStreaming = true
        streamError = nil
        startChunkBuffering()
        let messages = processor.buildMessages(input: originalInput, feedback: feedback, template: currentTemplate, context: currentContext)
        streamTask = llm.streamChat(
            messages: messages,
            onChunk: { [weak self] chunk in
                guard let self else { return }
                let remaining = 16_000 - self.streamedResult.count - self.chunkBuffer.count
                guard remaining > 0 else { return }
                self.chunkBuffer += String(chunk.prefix(remaining))
            },
            onDone: { [weak self] in
                self?.stopChunkBuffering()
                self?.isStreaming = false
                if self?.settings.playCompletionSound == true {
                    NSSound(named: "Tink")?.play()
                }
            },
            onError: { [weak self] error in
                self?.streamError = error
            }
        )
    }

    private func startChunkBuffering() {
        stopChunkBuffering()
        chunkBuffer = ""
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.flushChunkBuffer()
        }
        flushTimer = timer
        timer.resume()
    }

    private func stopChunkBuffering() {
        flushTimer?.cancel()
        flushTimer = nil
        flushChunkBuffer()
    }

    private func flushChunkBuffer() {
        guard !chunkBuffer.isEmpty, streamedResult.count < 16_000 else {
            chunkBuffer = ""
            return
        }
        let remaining = 16_000 - streamedResult.count
        guard remaining > 0 else {
            chunkBuffer = ""
            return
        }
        let chunk = String(chunkBuffer.prefix(remaining))
        streamedResult += chunk
        chunkBuffer.removeFirst(chunk.count)
    }
}
