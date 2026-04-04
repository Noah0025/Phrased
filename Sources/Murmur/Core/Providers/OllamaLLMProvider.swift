import Foundation

class OllamaLLMProvider: LLMProvider {
    private let client: OllamaClient

    init(model: String = "qwen2.5:7b") {
        self.client = OllamaClient(model: model)
    }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        let ollamaMessages = messages.map { OllamaMessage(role: $0.role, content: $0.content) }
        return client.streamChat(messages: ollamaMessages, onChunk: onChunk, onDone: onDone)
    }
}
