import Foundation

enum LLMRole: String {
    case system, user, assistant
}

struct LLMMessage {
    let role: LLMRole
    let content: String
}

protocol LLMProvider {
    @discardableResult
    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> Task<Void, Never>
}
