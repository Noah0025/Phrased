import XCTest
import Murmur

final class OllamaClientTests: XCTestCase {
    func test_buildRequest_hasCorrectMethod() {
        let client = OllamaClient(model: "qwen2.5:7b")
        let request = client.buildRequest(messages: [
            OllamaMessage(role: "user", content: "hello")
        ])
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func test_buildRequest_hasJSONContentType() {
        let client = OllamaClient(model: "qwen2.5:7b")
        let request = client.buildRequest(messages: [
            OllamaMessage(role: "user", content: "hello")
        ])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func test_buildRequest_bodyContainsModel() throws {
        let client = OllamaClient(model: "qwen2.5:7b")
        let request = client.buildRequest(messages: [
            OllamaMessage(role: "user", content: "hello")
        ])
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "qwen2.5:7b")
        XCTAssertEqual(json["stream"] as? Bool, true)
    }
}
