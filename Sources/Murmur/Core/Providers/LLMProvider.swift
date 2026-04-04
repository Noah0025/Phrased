import Foundation

struct LLMMessage {
    let role: String
    let content: String
}

protocol LLMProvider {
    @discardableResult
    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>
}
