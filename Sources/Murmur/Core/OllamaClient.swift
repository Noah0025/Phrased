import Foundation

public struct OllamaMessage {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public class OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434/api/chat")!
    public let model: String

    public init(model: String = "qwen2.5:7b") {
        self.model = model
    }

    /// Build a URLRequest for the given messages. Exposed for testing.
    public func buildRequest(messages: [OllamaMessage]) -> URLRequest {
        let body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]
        var request = URLRequest(url: baseURL, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Stream a chat completion, calling onChunk for each token, onDone when finished.
    public func streamChat(
        messages: [OllamaMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        return Task {
            let request = buildRequest(messages: messages)
            guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                await onDone()
                return
            }
            do {
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard !line.isEmpty,
                          let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let message = json["message"] as? [String: Any],
                          let content = message["content"] as? String,
                          !content.isEmpty else { continue }
                    await onChunk(content)
                    if let done = json["done"] as? Bool, done { break }
                }
            } catch {}
            await onDone()
        }
    }
}
