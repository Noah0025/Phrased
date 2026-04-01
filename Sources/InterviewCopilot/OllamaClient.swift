import Foundation

class OllamaClient {
    private let baseURL = URL(string: "http://localhost:11434/api/chat")!
    private let translateModel = "gemma3:4b"
    private let fastModel = "gemma3:4b"

    /// Warmup: send a tiny request to pre-load model into memory
    func warmup() {
        Task {
            let messages: [[String: String]] = [["role": "user", "content": "hi"]]
            let body: [String: Any] = ["model": translateModel, "messages": messages, "stream": false]
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
            var request = URLRequest(url: baseURL, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    // MARK: - Feature 1: Streaming translation
    func streamTranslation(prompt: String, onChunk: @escaping (String) -> Void) async {
        var messages: [[String: String]] = [["role": "user", "content": prompt]]
        let body: [String: Any] = ["model": translateModel, "messages": messages, "stream": true]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: baseURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else { return }
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      !content.isEmpty else { continue }
                // Call onChunk directly in async context (not via GCD)
                // so Task.isCancelled works correctly in the callback
                onChunk(content)
                if let done = json["done"] as? Bool, done { break }
            }
        } catch { }
    }

    // MARK: - Feature 2: Answer suggestion (streaming)
    func suggestAnswer(
        question: String,
        context: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        let systemPrompt = """
        You are an interview assistant helping Ningzhou Li in a PhD interview.
        Answer based ONLY on the provided context. Be concise — bullet points, max 5 points.
        Always respond in English.

        === CANDIDATE CONTEXT ===
        \(context)
        """

        let userPrompt = "The interviewer just asked: \"\(question)\"\n\nProvide 3-5 key answer points I should mention:"

        Task {
            await chatStream(model: fastModel, systemPrompt: systemPrompt, userPrompt: userPrompt, onChunk: onChunk, onComplete: onComplete)
        }
    }

    // MARK: - Feature 3: Streaming chat with system prompt (for subtitle correction + translation)
    func streamChat(
        systemPrompt: String,
        userPrompt: String,
        onChunk: @escaping (String) -> Void
    ) async {
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]
        let body: [String: Any] = ["model": fastModel, "messages": messages, "stream": true]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: baseURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else { return }
        do {
            for try await line in bytes.lines {
                if Task.isCancelled { return }
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      !content.isEmpty else { continue }
                onChunk(content)
                if let done = json["done"] as? Bool, done { break }
            }
        } catch { }
    }

    // MARK: - Core HTTP

    private func chat(model: String, systemPrompt: String?, userPrompt: String, stream: Bool) async -> String? {
        var messages: [[String: String]] = []
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: baseURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (responseData, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }
        return content
    }

    private func chatStream(
        model: String,
        systemPrompt: String?,
        userPrompt: String,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) async {
        var messages: [[String: String]] = []
        if let sys = systemPrompt {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": userPrompt])

        let body: [String: Any] = ["model": model, "messages": messages, "stream": true]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { onComplete(); return }

        var request = URLRequest(url: baseURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else {
            onComplete(); return
        }

        do {
            for try await line in bytes.lines {
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let message = json["message"] as? [String: Any],
                      let content = message["content"] as? String else { continue }
                DispatchQueue.main.async { onChunk(content) }
                if let done = json["done"] as? Bool, done { break }
            }
        } catch {
        }
        DispatchQueue.main.async { onComplete() }
    }
}
