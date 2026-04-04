import XCTest
@testable import Murmur

final class IntentProcessorTests: XCTestCase {
    func test_buildMessages_hasUserMessage() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "搞定这件事", feedback: nil)
        XCTAssertEqual(messages.last?.role, "user")
        XCTAssertTrue(messages.last?.content.contains("搞定这件事") == true)
    }

    func test_buildMessages_withFeedback_appendsFeedback() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "搞定这件事", feedback: "更正式一些")
        let userMessage = messages.last { $0.role == "user" }
        XCTAssertTrue(userMessage?.content.contains("更正式一些") == true)
    }

    func test_buildMessages_withStyle_injectsStyleInstruction() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "hello", feedback: nil, style: .formal)
        let userMessage = messages.last { $0.role == "user" }
        XCTAssertTrue(userMessage?.content.contains("正式") == true)
    }

    func test_buildMessages_autoStyle_noStyleInstruction() {
        let processor = IntentProcessor()
        let messages = processor.buildMessages(input: "hello", feedback: nil, style: .auto)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, "user")
    }
}
