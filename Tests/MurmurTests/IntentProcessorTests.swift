import XCTest
@testable import Murmur

final class IntentProcessorTests: XCTestCase {
    func test_buildMessages_withoutProfile_hasUserMessage() {
        let processor = IntentProcessor(profile: UserProfile())
        let messages = processor.buildMessages(input: "搞定这件事", feedback: nil)
        XCTAssertEqual(messages.last?.role, "user")
        XCTAssertTrue(messages.last?.content.contains("搞定这件事") == true)
    }

    func test_buildMessages_withProfile_injectsProfileIntoSystem() {
        var profile = UserProfile()
        profile.historySummary = "User prefers concise formal English"
        let processor = IntentProcessor(profile: profile)
        let messages = processor.buildMessages(input: "搞定这件事", feedback: nil)
        let systemMessage = messages.first { $0.role == "system" }
        XCTAssertNotNil(systemMessage)
        XCTAssertTrue(systemMessage?.content.contains("concise formal English") == true)
    }

    func test_buildMessages_withFeedback_appendsFeedbackToUser() {
        let processor = IntentProcessor(profile: UserProfile())
        let messages = processor.buildMessages(input: "搞定这件事", feedback: "更正式一些")
        let userMessage = messages.last { $0.role == "user" }
        XCTAssertTrue(userMessage?.content.contains("更正式一些") == true)
    }

    func test_buildMessages_withoutProfile_hasNoSystemMessage() {
        let processor = IntentProcessor(profile: UserProfile())
        let messages = processor.buildMessages(input: "hello", feedback: nil)
        let systemMessages = messages.filter { $0.role == "system" }
        XCTAssertTrue(systemMessages.isEmpty)
    }
}
