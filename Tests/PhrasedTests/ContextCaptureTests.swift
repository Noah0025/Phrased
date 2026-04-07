import XCTest
@testable import Phrased

final class ContextCaptureTests: XCTestCase {
    func test_captureReturnsValue() {
        let ctx = ContextCapture.capture()
        XCTAssertNotNil(ctx)
    }

    func test_emptyContext_isEmpty() {
        let ctx = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: nil)
        XCTAssertTrue(ctx.isEmpty)
    }

    func test_withClipboard_notEmpty() {
        let ctx = InputContext(frontmostApp: nil, selectedText: nil, clipboardText: "hello")
        XCTAssertFalse(ctx.isEmpty)
    }
}
