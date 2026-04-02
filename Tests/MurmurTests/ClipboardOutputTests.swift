import XCTest
@testable import Murmur

final class ClipboardOutputTests: XCTestCase {
    func test_copy_writesStringToClipboard() {
        ClipboardOutput.copy("hello murmur")
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, "hello murmur")
    }

    func test_copy_overwritesPreviousContent() {
        ClipboardOutput.copy("first")
        ClipboardOutput.copy("second")
        let pasted = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(pasted, "second")
    }
}
