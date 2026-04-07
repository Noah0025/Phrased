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
        onDone: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) -> Task<Void, Never> {
        Task {
            guard let url = URL(string: "\(baseURL)\(Self.chatCompletionsPath(for: baseURL))") else {
                await onError(NSLocalizedString("error.llm.invalid_url", comment: ""))
                await onDone()
                return
            }
            let body: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                "stream": true
            ]
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    await onError(
                        String(
                            format: NSLocalizedString("error.llm.server_error_format", comment: ""),
                            httpResponse.statusCode
                        )
                    )
                    await onDone()
                    return
                }
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
            } catch is CancellationError {
            } catch let error as URLError {
                switch error.code {
                case .timedOut:
                    await onError(NSLocalizedString("error.llm.timeout", comment: ""))
                case .notConnectedToInternet, .networkConnectionLost:
                    await onError(NSLocalizedString("error.llm.network_unavailable", comment: ""))
                default:
                    await onError(NSLocalizedString("error.llm.unknown", comment: ""))
                }
            } catch {
                await onError(NSLocalizedString("error.llm.unknown", comment: ""))
            }
            await onDone()
        }
    }

    /// Returns "/chat/completions" if the base URL already ends with a version segment
    /// (e.g. /v1, /v4), otherwise "/v1/chat/completions".
    static func chatCompletionsPath(for baseURL: String) -> String {
        let versionPattern = #"/v\d+$"#
        if baseURL.range(of: versionPattern, options: .regularExpression) != nil {
            return "/chat/completions"
        }
        return "/v1/chat/completions"
    }
}
