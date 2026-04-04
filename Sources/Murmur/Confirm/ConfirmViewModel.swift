import Foundation
import Combine

@MainActor
class ConfirmViewModel: ObservableObject {
    @Published var originalInput: String = ""
    @Published var streamedResult: String = ""
    @Published var isStreaming: Bool = false
    @Published var feedbackText: String = ""
    @Published var showFeedbackField: Bool = false
    @Published var didCopy: Bool = false
    @Published var isLocked: Bool = false
    private(set) var currentTemplate: PromptTemplate = PromptTemplate.builtins[0]
    private(set) var currentContext: InputContext = .empty

    private var llm: LLMProvider
    private let processor: IntentProcessor
    private var streamTask: Task<Void, Never>?

    var onDismiss: (() -> Void)?

    init(llm: LLMProvider, processor: IntentProcessor) {
        self.llm = llm
        self.processor = processor
    }

    func updateProvider(_ newLLM: LLMProvider) {
        llm = newLLM
    }

    func start(input: String, template: PromptTemplate = PromptTemplate.builtins[0], context: InputContext = .empty) {
        originalInput = input
        currentTemplate = template
        currentContext = context
        streamedResult = ""
        feedbackText = ""
        showFeedbackField = false
        didCopy = false
        generate(feedback: nil)
    }

    func regenerate() {
        let feedback = feedbackText.isEmpty ? nil : feedbackText
        streamedResult = ""
        showFeedbackField = false
        feedbackText = ""
        generate(feedback: feedback)
    }

    func accept() {
        ClipboardOutput.copy(streamedResult)
        didCopy = true
        if !isLocked {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.onDismiss?()
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        isLocked = false
        onDismiss?()
    }

    private func generate(feedback: String?) {
        streamTask?.cancel()
        isStreaming = true
        let messages = processor.buildMessages(input: originalInput, feedback: feedback, template: currentTemplate, context: currentContext)
        streamTask = llm.streamChat(
            messages: messages,
            onChunk: { [weak self] chunk in
                self?.streamedResult += chunk
            },
            onDone: { [weak self] in
                self?.isStreaming = false
            }
        )
    }
}
