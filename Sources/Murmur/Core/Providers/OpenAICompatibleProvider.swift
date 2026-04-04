import Foundation

/// Supports OpenAI, Groq, Moonshot, DeepSeek, llama.cpp, and any OpenAI-compatible API.
class OpenAICompatibleProvider: LLMProvider {
    private let baseURL: String
    private let apiKey: String
    private let model: String

    init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.apiKey = apiKey
        self.model = model
    }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
                await onDone(); return
            }
            let body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role, "content": $0.content] },
                "stream": true
            ]
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
                await onDone(); return
            }
            do {
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    guard line.hasPrefix("data: ") else { continue }
                    let payload = String(line.dropFirst(6))
                    if payload == "[DONE]" { break }
                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String,
                          !content.isEmpty else { continue }
                    await onChunk(content)
                }
            } catch {}
            await onDone()
        }
    }
}
