import XCTest
@testable import Murmur

final class LLMProviderTests: XCTestCase {
    func test_mockProvider_streamsChunks() async {
        let mock = MockLLMProvider(response: "hello world")
        var collected = ""
        let task = mock.streamChat(
            messages: [LLMMessage(role: "user", content: "hi")],
            onChunk: { collected += $0 },
            onDone: {}
        )
        await task.value
        XCTAssertEqual(collected, "hello world")
    }

    func test_ollamaProvider_conformsToProtocol() {
        let provider: LLMProvider = OllamaLLMProvider(model: "qwen2.5:7b")
        XCTAssertNotNil(provider)
    }

    func test_openAIProvider_conformsToProtocol() {
        let provider: LLMProvider = OpenAICompatibleProvider(
            baseURL: "https://api.openai.com", apiKey: "sk-test", model: "gpt-4o-mini"
        )
        XCTAssertNotNil(provider)
    }
}

class MockLLMProvider: LLMProvider {
    let response: String
    init(response: String) { self.response = response }

    func streamChat(
        messages: [LLMMessage],
        onChunk: @escaping @MainActor (String) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task {
            await onChunk(response)
            await onDone()
        }
    }
}
