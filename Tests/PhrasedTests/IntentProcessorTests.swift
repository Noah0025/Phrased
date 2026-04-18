import XCTest
@testable import Phrased

final class IntentProcessorTests: XCTestCase {
    func test_buildMessages_hasUserMessage() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "搞定这件事", feedback: nil)
        XCTAssertEqual(messages.last?.role, .user)
        XCTAssertTrue(messages.last?.content.contains("搞定这件事") == true)
    }

    func test_buildMessages_withFeedback_appendsFeedback() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "搞定这件事", feedback: "更正式一些")
        let userMessage = messages.last { $0.role == .user }
        XCTAssertTrue(userMessage?.content.contains("更正式一些") == true)
    }

    func test_buildMessages_withTemplate_injectsInstruction() {
        let processor = IntentProcessor()
        let formal = PromptTemplate.builtins.first { $0.id == "formal" }!
        let messages = processor.buildMessages(input: "hello", feedback: nil, template: formal)
        // formal template has a non-nil promptInstruction → system message contains "风格要求"
        let systemMessage = messages.first { $0.role == .system }
        XCTAssertTrue(systemMessage?.content.contains("风格要求") == true)
        // two messages: system + user
        XCTAssertEqual(messages.count, 2)
    }

    func test_buildMessages_autoTemplate_noStyleInstruction() {
        let processor = IntentProcessor()
        let auto = PromptTemplate.builtins[0]  // "auto" has nil promptInstruction
        let messages = processor.buildMessages(input: "hello", feedback: nil, template: auto)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .user)
        // without an app context, auto template adds no style instruction
        XCTAssertFalse(messages[0].content.contains("风格要求"))
    }
}
